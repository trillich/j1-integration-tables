SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[MCM_GetAdvocateSchedule]
    @daysago as int = 1
WITH EXECUTE AS 'dbo'
AS
-- =============================================
-- Author:		Will Trillich (Serensoft)	
-- Create date: 9/12/2024
-- Description:	Generate Symplicity ADVOCATE export data
-- Modified:	
--	
-- =============================================
BEGIN
        set nocount on;

        -- declare @daysago int = 80;

        declare @cterm as varchar(6) = dbo.MCM_FN_CALC_TRM('CF') -- "current fall"
        declare @curyr as int
        declare @nterm as varchar(6) = dbo.MCM_FN_CALC_TRM('CS') -- "current spring"
        declare @nxtyr as int

        -- print @cterm + ':' + @nterm;

        set @curyr = cast(left(@cterm,4) as int);
        set @nxtyr = cast(left(@nterm,4) as int);

        SET @cterm = right(@cterm,2); -- SS
        set @nterm = right(@nterm,2);
        -- print 'cterm='+@cterm+', yrs=['+@prevyr+','+@curyr+','+@nxtyr+']';

WITH
cte_reg_stu
    AS (
        -- declare @curyr int = 2023;
        -- declare @cterm varchar(2) = 'FA';
        -- declare @nxtyr int = 2023;
        -- declare @nterm varchar(2) = 'SP';
        
        SELECT
                ID_NUM,
                CRS_CDE,
                YR_CDE,
                TRM_CDE,
                TRANSACTION_STS
         FROM   student_crs_hist sch with (nolock)
         WHERE  stud_div IN ( 'UG', 'GR' )
                AND (
                    ( YR_CDE = @curyr and TRM_CDE = @cterm )
                    OR
                    ( YR_CDE = @nxtyr and TRM_CDE = @nterm )
                )
                AND transaction_sts IN ( 'C', 'D' )
                AND JOB_TIME > getdate() - @daysago
        ),
cte_sched
    as (
        -- declare @curyr int = 2023;
        -- declare @cterm varchar(2) = 'FA';
        -- declare @nxtyr int = 2023;
        -- declare @nterm varchar(2) = 'SP';

        SELECT
            ss.YR_CDE,
            ss.TRM_CDE,
            ss.CRS_CDE,
            replace(
                ss.MONDAY_CDE + ss.TUESDAY_CDE + ss.WEDNESDAY_CDE + ss.THURSDAY_CDE + ss.FRIDAY_CDE + ss.SATURDAY_CDE + ss.SUNDAY_CDE,
                ' ',
                '-'
            ) weekdays,
            -- FORMAT(ss.BEGIN_DTE,'M/d/yyyy')    begin_dte,
            -- FORMAT(ss.END_DTE,'M/d/yyyy')      end_dte,
            FORMAT(ss.BEGIN_TIM, 'HHmm')       begin_tim,
            FORMAT(ss.END_TIM,   'HHmm')       end_tim,
            sm.CRS_TITLE,
            ss.BLDG_CDE,
            ss.ROOM_CDE
        from
            SECTION_SCHEDULES ss with (nolock)
            JOIN
            section_master sm with (nolock)
            on ( ss.CRS_CDE = sm.CRS_CDE and ss.YR_CDE = sm.YR_CDE and ss.TRM_CDE = sm.TRM_CDE )
        where
            (ss.YR_CDE = @curyr and ss.TRM_CDE = @cterm)
            or
            (ss.YR_CDE = @nxtyr and ss.TRM_CDE = @nterm)
    )

SELECT 
    stu.id_num                              ID,
    schd.CRS_TITLE                          COURSE_TITLE,
    schd.CRS_CDE                            COURSE,
    schd.begin_tim                          START_TIME,
    schd.end_tim                            END_TIME,
    schd.weekdays                           DAYS,
    schd.BLDG_CDE                           BLDG,
    schd.ROOM_CDE                           ROOM,
    case
        when stu.TRANSACTION_STS = 'D'
        then 'DELETE'
        else ''
        end                                 delete_flag
FROM
    cte_reg_stu stu
    JOIN
    cte_sched schd
    on ( stu.CRS_CDE = schd.CRS_CDE and stu.TRM_CDE = schd.TRM_CDE and stu.YR_CDE = schd.YR_CDE )
;

    set nocount off;
    REVERT
END

;
GO
