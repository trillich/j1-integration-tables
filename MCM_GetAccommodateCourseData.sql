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

-- defaults for testing:
declare @curyr int; -- = 2024;
declare @cterm varchar(6); -- = 'FA';
-- declare @daysago int = 68;
select @cterm = dbo.MCM_FN_CALC_TRM('C'); -- YYYYSS for example: 2024FA
-- print @cterm;
set @curyr = cast(left(@cterm,4) as int);
SET @cterm = right(@cterm,2); -- SSYYYY (not YYYYSS)

-- print @cterm + ':' + cast(@curyr as varchar(4));

with
cte_sched
as (
    -- declare @curyr int = 2024;
    -- declare @cterm char(2) = 'FA';
    select
        ROW_NUMBER() over (partition by crs_cde order by MONDAY_CDE,TUESDAY_CDE,WEDNESDAY_CDE,THURSDAY_CDE,FRIDAY_CDE) rownum,
        ss.CRS_CDE,
        replace(ss.SUNDAY_CDE+ss.MONDAY_CDE+ss.TUESDAY_CDE+ss.WEDNESDAY_CDE+ss.THURSDAY_CDE+ss.FRIDAY_CDE+ss.SATURDAY_CDE,' ','-') sched,
        FORMAT(ss.BEGIN_DTE, 'M/d/yyyy')    begin_dte,
        FORMAT(ss.END_DTE,   'M/d/yyyy')    end_dte,
        FORMAT(ss.BEGIN_TIM, 'HHmm')        begin_tim,
        FORMAT(ss.END_TIM,   'HHmm')        end_tim
    from
        SECTION_SCHEDULES ss with (nolock)
    where
        ss.YR_CDE = @curyr
    and ss.TRM_CDE = @cterm
    -- and ss.CRS_CDE = 'NUR  2000LL'
    -- order by 1 desc
)
-- select * from cte_sched where rownum > 1
,
cte_fac as (
    -- declare @curyr int = 2024;
    -- declare @cterm char(2) = 'FA';
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
        fl.YR_CDE = @curyr
    and fl.TRM_CDE = @cterm
    -- and fl.CRS_CDE = 'NUR  2000LL'
)
-- select * from cte_fac
,
cte_reg_stu
AS (
    -- declare @curyr int = 2024;
    -- declare @cterm char(2) = 'FA';
    -- declare @daysago int = 999;
    SELECT
        sch.id_num,
        sch.CRS_CDE,
        replace(sch.CRS_CDE,' ','') course_code,
        sch.GRADE_CDE,
        case
            when sch.TRANSACTION_STS = 'C'
            then 'Y'
            else 'N'
            END                     enrolled,
        case
            when sch.TRANSACTION_STS = 'C'
            then ''
            else format(sch.DROP_DTE, 'M/d/yyyy')
            END                     enroll_ended_date,
        sm.CRS_TITLE,
        sm.CREDIT_HRS,
        sm.SUBTERM_CDE,
        sm.TRM_CDE,
        sm.YR_CDE,
        sm.FIRST_BEGIN_DTE,
        sm.LAST_END_DTE
    FROM
        student_crs_hist sch with (nolock)
        join
        section_master sm
        on (sch.CRS_CDE = sm.CRS_CDE and sch.YR_CDE = sm.YR_CDE and sch.TRM_CDE = sm.TRM_CDE)
    WHERE  sch.stud_div IN ( 'UG', 'GR' )
        AND sch.YR_CDE = @curyr
        AND sch.TRM_CDE = @cterm
        AND sch.transaction_sts IN ( 'H', 'C', 'D' )
        and sch.JOB_TIME > getdate() - @daysago -- the One True Filter
        -- and sch.CRS_CDE like 'NUR  2000L'
    -- order by 2,1
)
-- select * from cte_reg_stu;

SELECT 
    trim(
        replace(rs.crs_title,' ','_') + replace(rs.crs_cde,' ','')
        + '_'
        + @cterm + cast(@curyr as char(4))
        -- + case when left(@cterm,2) in ('FA','SP') then '' else sm.SUBTERM_CDE end
        + rs.SUBTERM_CDE
    )                               course_unique_id
    ,rs.id_num                      student_id
    ,rs.CRS_TITLE                   course_title
    ,rs.course_code
    ,rs.CREDIT_HRS                  credit_hours
    ,case
        when rs.TRM_CDE = 'FA' then 'Fall '
        when rs.TRM_CDE = 'SP' then 'Spring '
        when rs.TRM_CDE = 'WI' then 'Winter '
        when rs.TRM_CDE = 'SU' then 'Summer '
        else '?'
        end
        + rs.YR_CDE                 semester
    ,format(rs.FIRST_BEGIN_DTE,'M/d/yyyy')             start_date
    ,format(rs.LAST_END_DTE,'M/d/yyyy')                end_date
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
    ,rs.enrolled
    ,rs.enroll_ended_date
    ,rs.GRADE_CDE                   grade
    ,fac2.FIRST_NAME                inst_fname_2
    ,fac2.LAST_NAME                 inst_lname_2
    ,fac2.fullname                  instr_name_2
    ,fac2.alfaname                  instr_sortname_2
    ,fac2.AlternateContact          instr_email_2
    ,fac2.INSTRCTR_ID_NUM           inst_id_2
    ,fac3.FIRST_NAME                inst_fname_3
    ,fac3.LAST_NAME                 inst_lname_3
    ,fac3.fullname                  inst_name_3
    ,fac3.alfaname                  inst_sortname_3
    ,fac3.AlternateContact          instr_email_3
    ,fac3.INSTRCTR_ID_NUM           inst_id_3
         FROM   cte_reg_stu rs
                left join
                cte_fac fac1
                on (rs.CRS_CDE = fac1.CRS_CDE and fac1.rownum = 1)
                left join
                cte_fac fac2
                on (rs.CRS_CDE = fac2.CRS_CDE and fac2.rownum = 2)
                left join
                cte_fac fac3
                on (rs.CRS_CDE = fac3.CRS_CDE and fac3.rownum = 3)
                left join
                cte_sched sched1
                on (rs.CRS_CDE = sched1.CRS_CDE and sched1.rownum = 1)
                left join
                cte_sched sched2
                on (rs.CRS_CDE = sched2.CRS_CDE and sched1.rownum = 2)
                left join
                cte_sched sched3
                on (rs.CRS_CDE = sched3.CRS_CDE and sched1.rownum = 3)
-- where sched2.CRS_CDE > '!'
        order BY
            1,2;

    set nocount off;
    REVERT
END

;
GO
