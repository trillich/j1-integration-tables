SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[MCM_GetAccommodateCourseData](
    @daysago int
)

WITH EXECUTE AS 'dbo'
AS
-- =============================================
-- Author:		Will Trillich (Serensoft)	
-- Create date: 9/11/2024
-- Description:	Generate Accomodate Course data export
-- Modified:	

-- =============================================
BEGIN

declare @curyr int = 2024;
declare @cterm char(2) = 'FA';
-- declare @daysago int = 999;

with
cte_sched
as (
    select
        ROW_NUMBER() over (partition by crs_cde order by MONDAY_CDE,TUESDAY_CDE,WEDNESDAY_CDE,THURSDAY_CDE,FRIDAY_CDE) rownum,
        -- ss.YR_CDE,
        -- ss.TRM_CDE,
        ss.CRS_CDE,
        ss.MONDAY_CDE,
        ss.TUESDAY_CDE,
        ss.WEDNESDAY_CDE,
        ss.THURSDAY_CDE,
        ss.FRIDAY_CDE,
        ss.SATURDAY_CDE,
        ss.SUNDAY_CDE,
        replace(ss.SUNDAY_CDE+ss.MONDAY_CDE+ss.TUESDAY_CDE+ss.WEDNESDAY_CDE+ss.THURSDAY_CDE+ss.FRIDAY_CDE+ss.SATURDAY_CDE,' ','-') sched,
        FORMAT(ss.BEGIN_DTE,'M/d/yyyy')     begin_dte,
        FORMAT(ss.END_DTE,'M/d/yyyy')       end_dte,
        FORMAT(ss.BEGIN_TIM, 'HHmm')        begin_tim,
        FORMAT(ss.END_TIM, 'HHmm')          end_tim
    from
        SECTION_SCHEDULES ss with (nolock)
    where
        ss.YR_CDE = @curyr and
        ss.TRM_CDE = left(@cterm,2)
),
cte_fac as (
    SELECT
        ROW_NUMBER() OVER (PARTITION BY yr_cde,trm_cde,crs_cde ORDER BY instrctr_id_num) rownum
        ,fl.CRS_CDE
        ,fl.INSTRCTR_ID_NUM
        ,nm.FIRST_NAME
        ,nm.LAST_NAME
        ,nm.FIRST_NAME + ' ' + nm.LAST_NAME fullname
        ,nm.LAST_NAME + ', ' + nm.FIRST_NAME alfaname
        ,acm.AlternateContact
    FROM
        FACULTY_LOAD_TABLE fl with (nolock)
        JOIN
        NameMaster nm with (nolock)
        on nm.ID_NUM = fl.INSTRCTR_ID_NUM
        LEFT JOIN
        AlternateContactMethod acm with (nolock)
        on fl.INSTRCTR_ID_NUM = acm.ID_NUM and acm.ADDR_CDE = '*EML'
    WHERE
        fl.YR_CDE = @curyr and fl.TRM_CDE = left(@cterm,2)
)
SELECT
    trim(
        replace(sm.crs_title,' ','_') + replace(sch.crs_cde,' ','')
        + '_'
        + left(@cterm,2) + cast(@curyr as char(4))
        -- + case when left(@cterm,2) in ('FA','SP') then '' else sm.SUBTERM_CDE end
        + sm.SUBTERM_CDE
    )                               course_unique_id
    ,0 student_id -- FIXME
    ,sm.CRS_TITLE                   course_title
    ,replace(sch.crs_cde,' ','')    course_code
    ,sm.CREDIT_HRS                  credit_hours
    ,case
        when sm.TRM_CDE = 'FA' then 'Fall '
        when sm.TRM_CDE = 'SP' then 'Spring '
        when sm.TRM_CDE = 'WI' then 'Winter '
        when sm.TRM_CDE = 'SU' then 'Summer '
        else '?'
        end
        + sm.YR_CDE                 semester
    ,format(sm.FIRST_BEGIN_DTE,'M/d/yyyy')             start_date
    ,format(sm.LAST_END_DTE,'M/d/yyyy')                end_date
    ,sched1.sched                   days_1
    ,sched1.begin_tim               start_time_1
    ,sched1.end_tim                 end_time_1
    ,sched2.sched                   days_2
    ,sched2.begin_tim               start_time_2
    ,sched2.end_tim                 end_time_2
    ,sched3.sched                   days_3
    ,sched3.begin_tim               start_time_3
    ,sched3.end_tim                 end_time_3
    ,fac1.FIRST_NAME                inst_fname_1
    ,fac1.LAST_NAME                 inst_lname_1
    ,fac1.fullname                  inst_name_1
    ,fac1.alfaname                  inst_sortname_1
    ,fac1.AlternateContact          instr_email_1
    ,fac1.INSTRCTR_ID_NUM           inst_id_1
    ,'fixme'                        enrolled
    ,'fixme'                        enroll_ended_date
    ,'fixme'                        grade
    ,fac2.FIRST_NAME                inst_fname_2
    ,fac2.LAST_NAME                 inst_lname_2
    ,fac2.fullname                  inst_name_2
    ,fac2.alfaname                  inst_sortname_2
    ,fac2.AlternateContact          instr_email_2
    ,fac2.INSTRCTR_ID_NUM           inst_id_2
    ,fac3.FIRST_NAME                inst_fname_3
    ,fac3.LAST_NAME                 inst_lname_3
    ,fac3.fullname                  inst_name_3
    ,fac3.alfaname                  inst_sortname_3
    ,fac3.AlternateContact          instr_email_3
    ,fac3.INSTRCTR_ID_NUM           inst_id_3
         FROM   student_crs_hist sch
                join
                section_master sm
                on (sch.TRM_CDE = sm.TRM_CDE and sch.YR_CDE = sm.YR_CDE and sch.CRS_CDE = sm.CRS_CDE)
                left join
                cte_fac fac1
                on (fac1.CRS_CDE = sch.CRS_CDE and fac1.rownum = 1)
                left join
                cte_fac fac2
                on (fac2.CRS_CDE = sch.CRS_CDE and fac2.rownum = 2)
                left join
                cte_fac fac3
                on (fac3.CRS_CDE = sch.CRS_CDE and fac3.rownum = 3)
                left join
                cte_sched sched1
                on (sm.CRS_CDE = sched1.CRS_CDE and sched1.rownum = 1)
                left join
                cte_sched sched2
                on (sm.CRS_CDE = sched2.CRS_CDE and sched1.rownum = 2)
                left join
                cte_sched sched3
                on (sm.CRS_CDE = sched3.CRS_CDE and sched1.rownum = 3)

         WHERE  sch.stud_div IN ( 'UG', 'GR' )
                AND sch.YR_CDE = @curyr
                AND sch.TRM_CDE = left(@cterm,2)
                AND sch.transaction_sts IN ( 'H', 'C', 'D' )
                AND sch.job_time > getdate() - @daysago

    set nocount off;
    REVERT
END

;
GO

