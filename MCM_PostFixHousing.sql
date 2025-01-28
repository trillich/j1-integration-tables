SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		Will Trillich (Serensoft)	
-- Create date: 10-Jan-2025
-- Description:	For students with courses but no housing assignment, create placeholder housing record
-- Modified:	
-- 
-- =============================================
ALTER PROCEDURE [dbo].[MCM_PostFixHousing] 
AS

BEGIN

    -- transaction voodoo from https://rusanu.com/2009/06/11/exception-handling-and-nested-transactions/

	SET XACT_ABORT ON;
	SET NOCOUNT ON;

    DECLARE -- iterators
        @id_num int = 0,
        @sess varchar(10) = '';
    DECLARE -- local util vars
        @ct int = 0,
        @job varchar(30) = 'MCM_PostFixHousing',
        @msg varchar(999),
        @xct int = @@TRANCOUNT; -- already in a transaction?
    DECLARE -- cursor to iterate thru
        stu_crsr CURSOR FOR

        WITH
        cte_term as (
            -- active semesters
            select distinct
                term,
                year,
                term + year as sess
            from mcm_div_process
            where getdate() between active_date and inactive_date
        )
        -- select * from cte_term;
        ,
        cte_ssa as (
            -- students having stud_sess_assign already
            select 
                ssa.id_num,
                term.sess
            from 
                stud_sess_assign ssa
                    join
                cte_term term
                    on ssa.sess_cde = term.sess
        )
        -- select * from cte_ssa;
        ,
        cte_crs as (
            -- students having courses
            select distinct
                sch.id_num,
                term.sess
            from
                student_crs_hist sch
                    join
                cte_term term
                    on  sch.trm_cde = term.term
                    and sch.yr_cde  = term.year
            where
                sch.transaction_sts in ('C','H')
        )
        -- select crs.* from cte_crs crs;
        SELECT
            crs.id_num,
            crs.sess
        FROM
            cte_crs crs
            left join
            cte_ssa ssa
                on  crs.id_num = ssa.id_num
                and crs.sess   = ssa.sess
        WHERE
            ssa.id_num is null -- courses but no stud_sess_assign
        ;

    BEGIN TRY
        SET NOCOUNT ON;
        SET XACT_ABORT ON;

        if @xct = 0
            -- we weren't already in a transaction, so start one
            BEGIN TRANSACTION;
        else
            -- we were already in a transaction, so save it
            SAVE TRANSACTION @job;

        OPEN stu_crsr;
        FETCH NEXT FROM stu_crsr INTO @id_num, @sess;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            print 'id_num: ' + cast(@id_num as varchar(10)) + ', sess: ' + @sess;
            insert into STUD_SESS_ASSIGN (
                SESS_CDE,
                ID_NUM,
                RESID_COMMUTER_STS,
                -- and probably need some default values for these:
                ROOM_ASSIGN_STS,
                NUM_REQ_RMMATES,
                NUM_MATCH_RMMATES,
                AVAILABLE_AS_RMMATE
            ) values (
                @sess,
                @id_num,
                'C', -- this here is the main thing we're doing
                'N',
                0,
                0,
                'U'
            );
            SET @ct = @ct + 1;

            FETCH NEXT FROM stu_crsr INTO @id_num, @sess;
        END

        CLOSE stu_crsr;
        DEALLOCATE stu_crsr;

        if @xct = 0
            -- we weren't already in a transaction, but we made our own, so commit:
            COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH

        DECLARE @ErrorMessage NVARCHAR(4000);
        DECLARE @ErrorSeverity INT;
        DECLARE @ErrorState INT;
        DECLARE @XState INT;
        SELECT
            @ErrorMessage = ERROR_MESSAGE(),
            @ErrorSeverity = ERROR_SEVERITY(),
            @ErrorState = ERROR_STATE(),
            @XState = XACT_STATE();

        if @XState = -1
            ROLLBACK
        if @XState = 1 and @xct = 0
            ROLLBACK
        if @XState = 1 and @xct > 0
            ROLLBACK TRANSACTION @job;

		SET @msg = 'SP ' + @job + ' Ct=' + cast(@ct as varchar) + ', Error(' + Cast(Error_Number() AS varchar(10)) + '): ' + @ErrorMessage;

		exec MCM_Error_Handler @msg, @id_num, @job;
        RAISERROR (N'%s', @ErrorSeverity, @ErrorState, @msg );
    END CATCH

    REVERT;
END;

GO

/*,

SELECT
    id_num
FROM
	namemaster
inner join STUDENT_CRS_HIST sch on
	name_master.id_num = sch.id_num
	and
		(sch.YR_CDE = 2023
		and sch.TRM_CDE = 'SP')
left join STUD_SESS_ASSIGN ssa on
	name_master.id_num = ssa.ID_NUM
	and ssa.SESS_CDE = 'SP2024'
WHERE
	sch.TRANSACTION_STS IN ('C', 'H')
	and ssa.ID_NUM is null
;

-- create the ssa.resid_commuter_sts field = 'C"

*/





