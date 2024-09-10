SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[MCM_GetTHDschedules]

WITH EXECUTE AS 'dbo'
AS
-- =============================================
-- Author:		Will Trillich (Serensoft)	
-- Create date: 9/10/2024
-- Description:	Generate THD SCHEDULE data export
-- Modified:	
-- 
-- =============================================
BEGIN

        declare @cterm as varchar(6)
        declare @curyr as int
        set nocount on;

        select @cterm = dbo.MCM_FN_CALC_TRM('C');
        set @curyr = cast(left(@cterm,4) as int);

        SET @cterm = right(@cterm,2) + left(@cterm,4); -- SSYYYY (not YYYYSS)
        -- print 'cterm='+@cterm+', yrs=['+@prevyr+','+@curyr+','+@nxtyr+']';

WITH 
cte_sched
as (
    select *,
        case
            when monday + tuesday + wednesday + thursday + friday + saturday + sunday = 0
            then 'none'
            else ''
            end noweekdays
    from (
        select
            ss.YR_CDE,
            ss.TRM_CDE,
            ss.CRS_CDE,
            CASE WHEN isnull(ss.MONDAY_CDE,    '') > '' THEN -1 ELSE 0 END monday,
            CASE WHEN isnull(ss.TUESDAY_CDE,   '') > '' THEN -1 ELSE 0 END tuesday,
            CASE WHEN isnull(ss.WEDNESDAY_CDE, '') > '' THEN -1 ELSE 0 END wednesday,
            CASE WHEN isnull(ss.THURSDAY_CDE,  '') > '' THEN -1 ELSE 0 END thursday,
            CASE WHEN isnull(ss.FRIDAY_CDE,    '') > '' THEN -1 ELSE 0 END friday,
            CASE WHEN isnull(ss.SATURDAY_CDE,  '') > '' THEN -1 ELSE 0 END saturday,
            CASE WHEN isnull(ss.SUNDAY_CDE,    '') > '' THEN -1 ELSE 0 END sunday,
            FORMAT(BEGIN_DTE,'M/d/yyyy')    begin_dte,
            FORMAT(END_DTE,'M/d/yyyy')      end_dte,
            FORMAT(BEGIN_TIM, 'h:mm tt')    begin_tim,
            FORMAT(END_TIM, 'h:mm tt')      end_tim
        from
            SECTION_SCHEDULES ss with (nolock)
        where
            ss.YR_CDE = @curyr and
            ss.TRM_CDE = left(@cterm,2) -- FIXME
    ) x
),
cte_course_types
as (
    select
        td.TABLE_DESC as CRS_TYPE,
        secm.YR_CDE,
        secm.TRM_CDE,
        secm.SUBTERM_CDE,
        secm.DIVISION_CDE,
        secm.CRS_CDE,
        secm.CRS_TITLE 
    from section_master secm with (nolock)
        left join TABLE_DETAIL td with (nolock)
        on secm.CRS_TYPE = td.TABLE_VALUE AND td.COLUMN_NAME = 'crs_meeting_type'
    where
        secm.YR_CDE = @curyr and secm.TRM_CDE = left(@cterm,2)
),
cte_reg_stu
AS (
    SELECT id_num,
        CRS_CDE,
        TRM_CDE,
        YR_CDE,
        TRANSACTION_STS
    FROM   student_crs_hist with (nolock)
    WHERE  stud_div IN ( 'UG', 'GR' )
        AND YR_CDE = @curyr
        AND TRM_CDE = left(@cterm,2)
        AND transaction_sts IN ( 'H', 'C', 'D' )
)

-- end of CTE expressions

select
    r.ID_NUM        student_number,
    c.CRS_CDE       class_section_number,
    c.CRS_TITLE     class_section_name,
    s.BEGIN_DTE     class_start_date,
    s.END_DTE       class_end_date,
    s.BEGIN_TIM     class_start_time,
    s.END_TIM       class_end_time,
    s.sunday        meets_sunday,
    s.monday        meets_monday,
    s.tuesday       meets_tuesday,
    s.wednesday     meets_wednesday,
    s.thursday      meets_thursday,
    s.friday        meets_friday,
    s.saturday      meets_saturday,
    ''              instructor_name,
    ''              instructor_email
FROM
    cte_sched s
    join
    cte_reg_stu r
    on s.TRM_CDE = r.TRM_CDE and s.YR_CDE = r.YR_CDE and s.CRS_CDE = r.CRS_CDE
    join
    cte_course_types c
    on s.TRM_CDE = c.TRM_CDE and s.YR_CDE = c.YR_CDE and s.CRS_CDE = c.CRS_CDE
-- where s.thursday < 0

    set nocount off;
    REVERT
END

;
GO
