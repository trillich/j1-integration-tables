SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		Will Trillich (Serensoft)	
-- Create date: 7/29/2024...9/5/2024
-- Description:	Updates/inserts housing and meal plan assignments
-- Modified:	
--	
-- =============================================
ALTER PROCEDURE [dbo].[MCM_PostRoomAssign] 
-- params from INTGR_HOUSING columns:
	@trans_id as int,
	@id_num as int,
	@bldg_cde as varchar(4),
	@room_cde as varchar(4),
	@slot as int, -- moot, ignored
	@no_per_room as int, -- moot, ignored
	@meal_plan as varchar(2),
	@begins_dte as datetime = null,
	@ends_dte as datetime = null,
	@sess_cde as varchar(6), -- e.g. FA2024, SP2023
	@stat as varchar(1), -- A(ssignment) or R(emoval)
	@cancel_dte AS datetime = null,
	@cancel_rsn AS varchar(30) = null,
	@outtransid as int OUTPUT,
	@trancntmsg as varchar(500) OUTPUT

WITH EXECUTE AS 'dbo'
AS
BEGIN
	SET XACT_ABORT ON;
	SET NOCOUNT ON;

	BEGIN TRY
		BEGIN TRANSACTION;

		SET @trancntmsg = '';
		-- SET @trancntmsg = 'Implicit Transaction on? : ' + IIF(@@OPTIONS & 2 = 0, 'OFF', 'ON') + ' : Tran cnt after Begin Tran: ' + cast(@@TRANCOUNT as char(2)) + ' XACT_STATE = ' + cast(XACT_STATE() as char(2));

		DECLARE @Message VARCHAR(8000) = ''; 
		DECLARE @cur_loc_cde 			AS varchar(4);
		DECLARE @cur_bldg_cde 			AS varchar(4);
		DECLARE @cur_rm_cde 			AS varchar(4);
		DECLARE @cur_rm_slot_num 		AS int;
		DECLARE @cur_rm_num_residents 	AS int;
		DECLARE @cur_rm_num_vacancies 	AS int;
		DECLARE @cur_bldg_num_residents AS int;
		DECLARE @cur_resid_comm_sts 	AS varchar(4);
		DECLARE @cur_meal_plan 			AS varchar(4);

		DECLARE @meal_plan_only         AS int; -- might not have any room/dorm info, just a meal plan
        DECLARE @meal_plan_change       AS int;
        DECLARE @cancelling             AS int;

		DECLARE @new_loc_cde 			AS varchar(4);
	--	DECLARE @new_bldg_cde 			AS varchar(4);
	--  DECLARE @new_room_assign_sts 	AS varchar(4);
		DECLARE @new_room_slot 			AS int;
		DECLARE @new_rm_capacity 		AS int;
		DECLARE @new_rm_num_residents 	AS int;
		DECLARE @new_rm_num_vacancies 	AS int;
		DECLARE @new_bldg_num_residents AS int;

		DECLARE @room_change_reason     AS varchar(3);
		DECLARE @resid_commuter_sts		AS char(1);
		DECLARE @exit_dorm				AS bit; -- student leaving?
		DECLARE @enter_dorm 			AS bit; -- student entering?
        DECLARE @has_sess_assign        AS bit;

		DECLARE @user					AS varchar(513);
		DECLARE @job					AS varchar(30);
		DECLARE @debugger               AS varchar(250);
		DECLARE @msg                    AS varchar(500);

		--capture the actual user executing the SP
		SET @outtransid = @trans_id;
		SET @user = ORIGINAL_LOGIN();
		SET @job = 'MCM_PostRoomAssign';
		-- Defaults:
		SET @exit_dorm = 0;
		SET @enter_dorm = 0;
		SET @resid_commuter_sts = @cancel_rsn;
		SET @meal_plan_only = 0;
        SET @cancelling = 0;
		-- SET @trancntmsg = @trancntmsg + ' : Tran cnt Start: ' + cast(@@TRANCOUNT as char(2)) + ' XACT_STATE = ' + cast(XACT_STATE() as char(2));

		IF @@TRANCOUNT > 1 AND XACT_STATE() = 1
		BEGIN
			COMMIT TRANSACTION;
			-- SET @trancntmsg = @trancntmsg + ' : Tran cnt > 1 at beginning of execution so now committing: ' + cast(@@TRANCOUNT as char(2)) + ' XACT_STATE = ' + cast(XACT_STATE() as char(2));
		END

		---------------------------------------Preliminary Data Validation--------------------------------------------
		-- Gotta have a student id & session code
		IF isnull(@id_num,0) = 0
		BEGIN
			Raiserror( 'Student ID is required!', 16, 1 );
		END

		IF isnull(@sess_cde,'') = ''
		BEGIN
			Raiserror( 'Session code is required!', 16, 1 );
		END

        -- Location-code sanity check
		SELECT @new_loc_cde = loc_cde 
		FROM ROOM_MASTER 
		WHERE bldg_cde = @BLDG_CDE;

		IF isnull(@new_loc_cde,'x') = 'x'
		BEGIN
            if @meal_plan > '!'
            BEGIN
                set @meal_plan_only = 1
                set @resid_commuter_sts = 'C' -- legacy code? can't determine L or F tho :( FIXME
            END
            ELSE
            BEGIN
                Raiserror('Unknown building location code -- and no meal plan', 16, 1)
            END
		END

        IF @stat = 'R' or @cancel_rsn > '!' or @cancel_dte > cast('1/1/1970' as date)
        BEGIN
            SET @cancelling = 1;
        END

        if @meal_plan_only = 0
        BEGIN
            -- Building-code sanity check
            SELECT @new_bldg_num_residents = num_residents
            FROM SESS_BLDG_MASTER
            WHERE sess_cde =@sess_cde AND bldg_loc_cde =@new_loc_cde AND bldg_cde =@BLDG_CDE;

            IF isnull( @new_bldg_num_residents, -1 ) = -1
            BEGIN
                Raiserror('Building must be defined for session in SESS_BLDG_MASTER', 16, 1)
            END

            -- Room-code sanity check
            SELECT 
                @new_rm_capacity = room_capacity, 
                @new_rm_num_residents = num_residents, 
                @new_rm_num_vacancies = num_vacancies 
            FROM SESS_ROOM_MASTER
            WHERE sess_cde =@sess_cde AND bldg_loc_cde =@new_loc_cde AND bldg_cde =@BLDG_CDE AND room_cde =@ROOM_CDE;

            if isnull( @new_rm_capacity, -1 ) = -1
            BEGIN
                Raiserror('Room must be defined for session in SESS_ROOM_MASTER', 16, 1)
            END
        END

		---------------------- Gather CURRENT dorm info, if any ----------------------
        SET @debugger = 'Gathering prelim info';

		SELECT @has_sess_assign = CASE WHEN id_num is not null THEN 1 ELSE 0 END, 
			@cur_resid_comm_sts = resid_commuter_sts, 
			@cur_meal_plan = meal_plan
		FROM STUD_SESS_ASSIGN 
		WHERE sess_cde = @sess_cde AND id_num = @id_num;

        SET @meal_plan_change = 0
		--SET @trancntmsg = '@meal_plan_change = 0 | @meal_plan = ' + isnull(@meal_plan,'none') + ' | @cur_meal_plan = ' + isnull(@cur_meal_plan,'none');
        if (isnull(@meal_plan,'') <> '' OR isnull(@cur_meal_plan,'') <> '') and isnull(@meal_plan, '') <> isnull(@cur_meal_plan, '')
        BEGIN
            set @meal_plan_change = 1
			--SET @trancntmsg = '@meal_plan_change = 1';
        END

        -- set @msg = concat(@debugger, ' mpo:', @meal_plan_only, ', id=[', isnull(@id_num,'?'), '], sess=[', isnull(@sess_cde,'?'), ']');
        --PRINT @msg;

        if @meal_plan_only = 0
        BEGIN

            SELECT
                @cur_loc_cde     = bldg_loc_cde,
                @cur_bldg_cde    = bldg_cde,
                @cur_rm_cde      = room_cde,
                @cur_rm_slot_num = room_slot_num
            FROM ROOM_ASSIGN
            WHERE id_num = @id_num and sess_cde = @sess_cde;

            -- set @msg = concat(@debugger, 'cur_bldg=[', isnull(@cur_bldg_cde,'?'), '], cur_rm=[', isnull(@cur_rm_cde,'?'), ']');
            --PRINT @msg;

            SELECT
                @cur_rm_num_residents = num_residents,
                @cur_rm_num_vacancies = num_vacancies 
            FROM SESS_ROOM_MASTER
            WHERE sess_cde =@sess_cde AND bldg_loc_cde =@cur_loc_cde AND bldg_cde =@cur_bldg_cde AND room_cde =@cur_rm_cde;

            SELECT
                @cur_bldg_num_residents = num_residents 
            FROM SESS_BLDG_MASTER
            WHERE sess_cde =@sess_cde AND bldg_loc_cde =@cur_loc_cde AND bldg_cde =@cur_bldg_cde;
        END

		------------------------------------------------
		------------------- HOUSING --------------------
		------------------------------------------------

        SET @debugger = 'Determining status';

		if isnull(@bldg_cde, '') = '' or @cancelling > 0
		BEGIN --------- no incoming bldg_cde (commuter or withdrawn)

			if isnull(@cur_bldg_cde,'') = ''
			BEGIN -- no cur_bldg_cde
				-- no change, was a commuter before and is commuter still
				select 1
			END
			ELSE
			BEGIN ----------- WAS resident, NOW commuter (or withdrawn?)
				/* NOTE:
				SELECT table_value, table_desc FROM J1CONV.dbo.TABLE_DETAIL WHERE column_name = 'resid_commuter_sts'
				-- only shows C/R... nothing for leave-of-absence or withdrawal
				 */
				-- set @resid_commuter_sts = 'C' -- incoming status
				set @room_change_reason = 'COM' -- FIXME the EXP/FIN/HLT/INC/REP codes don't have a value for 'commuter'?
				if @cancelling > 0 -- we just need to know when it's a reasonable date
				begin
					SET @resid_commuter_sts = @cancel_rsn;
					SET @room_change_reason = @cancel_rsn;
				end

				SET @exit_dorm = 1;
			END

		END
		ELSE
		BEGIN --------- have incoming bldg_code: RESIDENT

            SET @resid_commuter_sts = 'R'

			if isnull(@cur_bldg_cde,'') = ''
			BEGIN -- was commuter, now resident
                set @enter_dorm = 1;
			END
			ELSE IF @bldg_cde = @cur_bldg_cde and @room_cde = @cur_rm_cde
			BEGIN -- same bldg/room as always, but are we cancelling?
				if @cancelling = 0
                BEGIN
                    -- same room and not being cancelled, so nothing to do:
                    set @exit_dorm = 0;
                    set @enter_dorm = 0;
                END
			END
			ELSE
			BEGIN -- bldg/room has CHANGED
				SET @exit_dorm = 1; -- leave old room
				SET @enter_dorm = 1; -- enter the new room
				SET @room_change_reason = 'REP' -- FIXME just guessing here, "preference"?
			END
		END

		-- SET @msg = concat('exit_dorm=', @exit_dorm, ', enter_dorm=', @enter_dorm);
		-- PRINT @msg;
		-------------------------------------------------
		-- Here's where the student leaves a dorm room --
		-------------------------------------------------

		if @exit_dorm = 1 -- student is moving OUT OF a dorm room
		BEGIN -------- do EXIT_DORM activity (became commuter or withdrew):
            SET @debugger = 'Exiting dorm';

			UPDATE STUD_SESS_ASSIGN 
			SET resid_commuter_sts =@resid_commuter_sts,
				meal_plan = CASE WHEN @resid_commuter_sts NOT IN ('F', 'L', 'C') THEN NULL ELSE @meal_plan END, 
				user_name = @user , 
				job_name = @job , 
				job_time = getdate() 
			WHERE sess_cde = @sess_cde AND id_num =@id_num;

			UPDATE SESS_BLDG_MASTER
			SET num_residents = @cur_bldg_num_residents - 1,
				num_vacancies = num_vacancies + 1,
				user_name = @user ,
				job_name = @job , 
				job_time = getdate() 
			WHERE sess_cde = @sess_cde and bldg_loc_cde = @cur_loc_cde and bldg_cde = @cur_bldg_cde;

			UPDATE SESS_ROOM_MASTER 
			SET 
				room_sts = 
					CASE WHEN @cur_rm_num_residents > 1 
					THEN 'P' 
					ELSE 'V' END , 
				num_residents =@cur_rm_num_residents - 1 , 
				num_vacancies =@cur_rm_num_vacancies + 1 , 
				user_name = @user,
				job_name = @job , 
				job_time = getdate()
			WHERE sess_cde =@sess_cde AND bldg_loc_cde =@cur_loc_cde AND bldg_cde =@cur_bldg_cde AND room_cde =@cur_rm_cde;

            set @cur_rm_num_residents = @cur_rm_num_residents - 1;
            set @cur_rm_num_vacancies = @cur_rm_num_vacancies + 1;

            -- removing a roommate makes all other roommates A[vailable]:
            UPDATE ssa SET ssa.available_as_rmmate = 'A'
            FROM STUD_SESS_ASSIGN ssa
                INNER JOIN STUD_ROOMMATES sr ON ssa.SESS_CDE = sr.SESS_CDE AND ssa.ID_NUM = sr.ROOMMATE_ID
            WHERE  sr.sess_cde =@sess_cde AND sr.bldg_loc_cde =@cur_loc_cde AND sr.bldg_cde =@cur_bldg_cde AND sr.room_cde =@cur_rm_cde AND sr.roommate_id = @id_num;

			DELETE FROM STUD_ROOMMATES 
			WHERE sess_cde =@sess_cde AND bldg_loc_cde =@cur_loc_cde AND bldg_cde =@cur_bldg_cde AND room_cde =@cur_rm_cde AND ( id_num =@id_num OR roommate_id =@id_num) 
				AND ( req_actual_flag ='A' OR req_actual_flag ='' OR req_actual_flag IS NULL );

			UPDATE STUD_SESS_ASSIGN 
			SET room_assign_sts ='U', 
				available_as_rmmate = 
					CASE WHEN @RESID_COMMUTER_STS NOT IN ('R') 
					THEN 'U' 
					ELSE 'A' END,
				user_name = @user ,
				job_name = @job ,
				job_time = getdate() 
			WHERE sess_cde =@sess_cde AND id_num =@id_num;

            UPDATE ROOM_ASSIGN
            SET id_num = NULL, 
				room_assign_sts = 'U', 
				ASSIGN_DTE = NULL, 
				user_name = @user ,
				job_name = @job ,
				job_time = getdate() 
            WHERE id_num = @id_num AND sess_cde = @sess_cde;

			INSERT INTO ROOM_CHANGE_HIST (
				sess_cde ,
				id_num ,
				room_change_dte ,
				old_bldg_loc_cde ,
				old_bldg_cde ,
				old_room_cde ,
				new_bldg_loc_cde ,
				new_bldg_cde ,
				new_room_cde , 
				room_change_reason ,
				room_change_comment ,
				user_name ,
				job_name ,
				job_time ) 
			VALUES (
				@sess_cde ,
				@id_num,
				getdate() ,
				@cur_loc_cde ,
				@cur_bldg_cde ,
				@cur_rm_cde ,
				null ,
				null ,
				null , 
				@room_change_reason ,
				null ,
				@user ,
				@job ,
				getdate() );
		END

		-------------------------------------------------
		-- Here's where the student enters a dorm room --
		-------------------------------------------------

		if @enter_dorm = 1 -- student is moving INTO a dorm room
		BEGIN -- do ENTER_DORM activity

            SET @debugger = 'Entering dorm';
			-- PRINT 'enter_dorm = 1'

			IF @has_sess_assign = 1
			BEGIN -- assignment already exists in STUD_SESS_ASSIGN

				-- PRINT 'cur_resid_comm_sts <> '''''

				UPDATE STUD_SESS_ASSIGN
				SET resid_commuter_sts =@resid_commuter_sts,
					meal_plan =@meal_plan , -- FIXME what if we don't have "new" @meal_plan ...but it should just stay as-is?
					user_name = @user ,
					job_name = @job ,
					job_time =getdate()
				WHERE sess_cde =@sess_cde AND id_num =@id_num;
			END
			ELSE
			BEGIN -- no assignment found in STUD_SESS_ASSIGN

				-- PRINT 'cur_resid_comm_sts is empty'

				INSERT INTO STUD_SESS_ASSIGN ( sess_cde, id_num, job_name, 
					room_assign_sts, resid_commuter_sts, meal_plan, available_as_rmmate, 
					override_phone, user_name, job_time ) 
				VALUES ( @sess_cde, @id_num, @job,
					'U', @resid_commuter_sts, @meal_plan, 'A',
					'N', @user, getdate());

				INSERT INTO STUD_SESS_ASGN_EXT (STUD_SESS_ASGN_EXT.SESS_CDE, 
					STUD_SESS_ASGN_EXT.ID_NUM, STUD_SESS_ASGN_EXT.udef_1a_1, 
					STUD_SESS_ASGN_EXT.udef_1a_2, STUD_SESS_ASGN_EXT.udef_1a_3, 
					STUD_SESS_ASGN_EXT.udef_2a_1, STUD_SESS_ASGN_EXT.udef_2a_2, 
					STUD_SESS_ASGN_EXT.udef_2a_3, STUD_SESS_ASGN_EXT.udef_3a_1, 
					STUD_SESS_ASGN_EXT.udef_3a_2, STUD_SESS_ASGN_EXT.udef_3a_3, 
					STUD_SESS_ASGN_EXT.udef_5a_1, STUD_SESS_ASGN_EXT.udef_5a_2, 
					STUD_SESS_ASGN_EXT.udef_5a_3, STUD_SESS_ASGN_EXT.udef_id_1, 
					STUD_SESS_ASGN_EXT.udef_id_2, STUD_SESS_ASGN_EXT.udef_dte_1, 
					STUD_SESS_ASGN_EXT.udef_dte_2, STUD_SESS_ASGN_EXT.udef_3_2_1, 
					STUD_SESS_ASGN_EXT.udef_5_2_1, STUD_SESS_ASGN_EXT.udef_5_2_2, 
					STUD_SESS_ASGN_EXT.udef_5_2_3, STUD_SESS_ASGN_EXT.udef_7_2_1, 
					STUD_SESS_ASGN_EXT.udef_7_2_2, STUD_SESS_ASGN_EXT.udef_11_2_1, 
					STUD_SESS_ASGN_EXT.udef_11_2_2) 
				VALUES (@sess_cde, @id_num, null, null, null, null, 
					null, null, null, null, null, null, null, null, 
					0, 0, null, null, 0, 0, 0, 0, 0, 0, 0, 0);
			END

            -- set @msg = @debugger + ' dorm=[' + isnull(@bldg_cde,'?') + '/' + isnull(@cur_bldg_cde,'?') + '], room=[' + isnull(@room_cde,'?') + '/' + isnull(@cur_rm_cde,'?') + ']';
            -- PRINT @msg;

			SELECT 
				@new_room_slot = min(ROOM_SLOT_NUM) 
			FROM room_assign 
			WHERE sess_cde = @SESS_CDE AND bldg_loc_cde = @new_loc_cde AND bldg_cde = @BLDG_CDE AND room_cde = @ROOM_CDE AND room_assign_sts = 'U'

			if isnull( @new_room_slot, -9 ) = -9
			BEGIN
				Raiserror('No unassigned slot for room in room_assign', 16, 1)
			END

			-- PRINT 'got new_room_slot ' + cast(@new_room_slot AS varchar)

			UPDATE STUD_SESS_ASSIGN
			SET room_assign_sts = 'A',
				resid_commuter_sts =@resid_commuter_sts ,
				meal_plan =@meal_plan ,
				available_as_rmmate = 
					CASE
                    WHEN @resid_commuter_sts IN ('C', 'F', 'L') 
					THEN 'U' 
                    WHEN @new_rm_num_vacancies <= 1
                    THEN 'U'
					ELSE 'A' END, 
				user_name = @user ,
				job_name = @job ,
				job_time = getdate()
			WHERE sess_cde =@SESS_CDE AND id_num =@id_num;

			UPDATE room_assign
			SET id_num = @ID_NUM,
				room_assign_sts = 'A',
				assign_dte = getdate(),
				user_name = @user,
				job_name = @job,
				job_time = getdate()
			WHERE sess_cde = @SESS_CDE AND bldg_loc_cde = @new_loc_cde AND bldg_cde = @BLDG_CDE AND room_cde = @ROOM_CDE AND room_slot_num = @new_room_slot;

			-------- ROOMMATES LOOP: --------
			DECLARE @roomie_id as int;

			DECLARE roomie_crsr CURSOR LOCAL FOR
            SELECT ra.id_num as RoommateID
            FROM ROOM_ASSIGN ra
            WHERE ra.sess_cde = @sess_cde AND ra.bldg_loc_cde = @new_loc_cde AND ra.bldg_cde = @BLDG_CDE AND ra.room_cde = @ROOM_CDE
                AND ra.ID_NUM <> @ID_NUM;

			OPEN roomie_crsr;

			FETCH NEXT FROM roomie_crsr into @roomie_id;
			WHILE @@FETCH_STATUS = 0
			BEGIN

                -- print concat('stud_roommates: ', @sess_cde, ' ', cast(@id_num as varchar), '/', cast(@roomie_id as varchar), ': @', @bldg_cde, @room_cde);

				INSERT INTO stud_roommates ( sess_cde, id_num, req_actual_flag, roommate_id, bldg_loc_cde, bldg_cde, room_cde, user_name, job_name, job_time ) 
				VALUES ( @SESS_CDE, @ID_NUM, 'A', @roomie_id, @new_loc_cde, @BLDG_CDE, @ROOM_CDE, @user, @job, getdate() );
				-- .................#######.......##########

				INSERT INTO stud_roommates ( sess_cde, id_num, req_actual_flag, roommate_id, bldg_loc_cde, bldg_cde, room_cde, user_name, job_name, job_time ) 
				VALUES ( @SESS_CDE, @roomie_id, 'A', @ID_NUM, @new_loc_cde, @BLDG_CDE, @ROOM_CDE, @user, @job, getdate() );
				-- .................##########.......#######

                if @new_rm_num_vacancies <= 1
                BEGIN
                    UPDATE STUD_SESS_ASSIGN
                    SET AVAILABLE_AS_RMMATE = 'U'
                    where SESS_CDE = @sess_cde and ID_NUM = @roomie_id;
                END

                FETCH NEXT FROM roomie_crsr into @roomie_id;

			END
			CLOSE roomie_crsr;
			DEALLOCATE roomie_crsr;
			-------- END ROOMMATES LOOP --------

			UPDATE sess_bldg_master
			SET num_residents = @new_bldg_num_residents + 1,
				user_name = @user ,
				job_name = @job ,
				job_time =getdate() 
			WHERE sess_cde =@SESS_CDE AND bldg_loc_cde =@new_loc_cde AND bldg_cde =@BLDG_CDE;

			UPDATE sess_room_master 
			SET room_sts = 
				CASE WHEN @new_rm_num_residents + 1 < @new_rm_capacity
				THEN 'P'
				WHEN @new_rm_num_residents + 1 = @new_rm_capacity
				THEN 'F'
				ELSE 'V' END,
			num_residents = @new_rm_num_residents + 1,
			num_vacancies = @new_rm_num_vacancies - 1,
			user_name = @user,
			job_name = @job ,
			job_time = getdate()
			WHERE sess_cde =@SESS_CDE AND bldg_loc_cde =@new_loc_cde AND bldg_cde =@BLDG_CDE AND room_cde =@ROOM_CDE;

		END
        ELSE IF @meal_plan_only = 1 or @meal_plan_change = 1
        BEGIN
            -- not entering dorm, but we do have a meal plan anyway

            IF isnull(@cur_resid_comm_sts,'') = '' -- no current stud_sess_assign
            BEGIN
				INSERT INTO STUD_SESS_ASSIGN ( sess_cde, id_num, job_name, 
					room_assign_sts, resid_commuter_sts, meal_plan, available_as_rmmate, 
					override_phone, user_name, job_time ) 
				VALUES ( @sess_cde, @id_num, @job,
					'U', 'C', @meal_plan, 'U', -- not roommate material?
					'N', @user, getdate());
            END
            ELSE
            BEGIN
                UPDATE STUD_SESS_ASSIGN 
                SET meal_plan = @meal_plan , 
                    user_name = @user , 
                    job_name = @job , 
                    job_time = getdate() 
                WHERE sess_cde = @sess_cde AND id_num =@id_num;

				SET @trancntmsg = @trancntmsg + ' | Meal Plan Updated';
            END

        END

        SET @debugger = 'Committing';
		-- PRINT 'Catch has not been triggered!';
		--SET @trancntmsg = @trancntmsg + ' : Tran cnt before Commit: ' + cast(@@TRANCOUNT as char(2)) + ' XACT_STATE = ' + cast(XACT_STATE() as char(2));
		COMMIT TRANSACTION;
		--SET @trancntmsg = @trancntmsg + ' : Tran cnt after Commit: ' + cast(@@TRANCOUNT as char(2)) + ' XACT_STATE = ' + cast(XACT_STATE() as char(2));

	END TRY
	BEGIN CATCH
		--Log error

		SET @Message = 'SP ' + @job + '[' + @debugger + '] Error(' + Cast(Error_Number() AS varchar(10)) + '): ' + Error_Message();

		DECLARE @errorseverity int;
		DECLARE @errorstate int;

		SELECT @errorseverity = ERROR_SEVERITY(), @errorstate = ERROR_STATE();

		--SET @trancntmsg = @trancntmsg + ' : Tran cnt enter Catch: ' + cast(@@TRANCOUNT as char(2)) + ' XACT_STATE = ' + cast(XACT_STATE() as char(2));
		IF (XACT_STATE()) = -1
		BEGIN
			ROLLBACK TRANSACTION;
			--SET @trancntmsg = @trancntmsg + ' : Tran cnt in Catch after Rollback: ' + cast(@@TRANCOUNT as char(2)) + ' XACT_STATE = ' + cast(XACT_STATE() as char(2));
		END
		IF (XACT_STATE()) = 1
		BEGIN
			COMMIT TRANSACTION;
			--SET @trancntmsg = @trancntmsg + ' : Tran cnt in Catch after Commit: ' + cast(@@TRANCOUNT as char(2)) + ' XACT_STATE = ' + cast(XACT_STATE() as char(2));
		END
		--SET @trancntmsg = @trancntmsg + ' : Tran cnt in Catch before log: ' + cast(@@TRANCOUNT as char(2))+ ' XACT_STATE = ' + cast(XACT_STATE() as char(2));
		-- SET @Message = @Message + ' : ' + @trancntmsg;

		exec MCM_Error_Handler @Message, @id_num, @job;
		RAISERROR(N'%s', @errorseverity, @errorstate, @Message);
				
	END CATCH
		

REVERT

END
GO
