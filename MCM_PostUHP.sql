SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		Will Trillich (Serensoft)	
-- Create date: 5/7/2025
-- Description:	Updates/inserts uhp data -- 
-- Modified:	
--	
-- =============================================
CREATE PROCEDURE [dbo].[MCM_PostUHP] 
-- params from INTGR_HOUSING columns:
	@trans_id as int,
	@id_num as int,
	@term_cde as varchar(6),
	@action as char(1), -- e=enrolled, n=not complete, w=waived
	@returnmsg as varchar(5000) OUTPUT

WITH EXECUTE AS 'dbo'
AS
BEGIN
	SET XACT_ABORT ON;
	SET NOCOUNT ON;

	SET @returnmsg = '';

	BEGIN TRY
		BEGIN TRANSACTION;

		DECLARE @found_student		AS int;
		DECLARE @had_waiver			AS char(1);
		DECLARE @new_waiver			AS char(1);

		DECLARE @user					AS varchar(513);
		DECLARE @job					AS varchar(30);
		DECLARE @debugger               AS varchar(250);
		DECLARE @msg                    AS varchar(500);

		--capture the actual user executing the SP
		SET @user = ORIGINAL_LOGIN();
		SET @job = 'MCM_PostUHP';
		-- Defaults:

		SET @new_waiver = '?';
		IF @action = 'W'
			SET @new_waiver = 'Y';
		IF @action in ('E','N')
			SET @new_waiver = 'N';

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

		-- IF isnull(@term_cde,'') = ''
		-- BEGIN
		-- 	Raiserror( 'Session code is required!', 16, 1 );
		-- END

		---------------------------------------Check For Existing Data--------------------------------------------

		-- Hmm: should we also confirm student is in STUDENT_CRS_HIST with yr_cde/term_cde or DEGREE_HISTORY?

		SELECT
			@found_student = [id_num],
			@had_waiver    = [health_ins_waiver]
		FROM [STUDENT_MASTER_UDF]
		WHERE [id_num] = @id_num; -- primary key is solely id_num

		IF isnull(@found_student,-1) = -1
		BEGIN

			set @returnmsg = 'Student ID new => inserting new record in STUDENT_MASTER_UDF table.';

			insert into 
			STUDENT_MASTER_UDF (
				 [ID_NUM] -- primary key
				,[USER_NAME]
				,[JOB_NAME]
				,[JOB_TIME]
				,[health_ins_waiver]
				,[health_ins_term]
			) values (
				 @id_num
				,@user
				,@job
				,getdate()
				,@new_waiver
				,@term_cde
			);
		END
		ELSE
		BEGIN

			set @returnmsg = 'Student ID already found in STUDENT_MASTER_UDF table; updating.';

			update STUDENT_MASTER_UDF
			set 
				 [USER_NAME] = @user
				,[JOB_NAME] = @job
				,[JOB_TIME] = getdate()
				,[health_ins_waiver] = @new_waiver
				,[health_ins_term] = @term_cde
			where
				[id_num] = @id_num -- primary key
		END

	END TRY
	BEGIN CATCH
		--Log error

		SET @returnmsg = 'SP ' + @job + '[' + @debugger + '] Error(' + Cast(Error_Number() AS varchar(10)) + '): ' + Error_Message();

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

		exec MCM_Error_Handler @returnmsg, @id_num, @job;
		RAISERROR(N'%s', @errorseverity, @errorstate, @returnmsg);

	END CATCH

REVERT

END
GO
