-- /*
-- not ready for prime time - placeholder - stick a pin in it

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[MCM_GetBBAfaculty](
    @daysago int
)

WITH EXECUTE AS 'dbo'
AS
-- =============================================
-- Author:		Will Trillich (Serensoft)	
-- Create date: 2/23/2025
-- Description:	Generate Accomodate Faculty data export
-- Modified:	

-- =============================================
BEGIN

-- defaults for testing:
declare @curyr int = 2024;
declare @cterm char(6) = 'FA';
-- declare @daysago int = 1000;

select @cterm = dbo.MCM_FN_CALC_TRM('C');
set @curyr = cast(left(@cterm,4) as int);
SET @cterm = right(@cterm,2) + left(@cterm,4); -- SSYYYY (not YYYYSS)
-- print @cterm;
with
cte_reg_stu
AS (
    -- declare @curyr int = 2024;
    -- declare @cterm char(2) = 'FA';
    -- declare @daysago int = 999;
    SELECT
        sch.CRS_CDE,
        sch.TRM_CDE,
        sch.YR_CDE
    FROM
        student_crs_hist sch with (nolock)
    WHERE  sch.stud_div IN ( 'UG', 'GR' )
        AND sch.YR_CDE = @curyr
        AND sch.TRM_CDE = left(@cterm,2)
        AND sch.transaction_sts IN ( 'H', 'C', 'D' )
        and sch.JOB_TIME > getdate() - @daysago -- the One True Filter
    --     and sch.CRS_CDE like 'NUR  2000L'
    GROUP BY
        crs_cde,trm_cde,yr_cde
    -- order by 2,1
),
cte_fac as (
    -- declare @curyr int = 2024;
    -- declare @cterm char(2) = 'FA';
    SELECT DISTINCT
        fl.CRS_CDE
        ,fl.INSTRCTR_ID_NUM
        ,nm.FIRST_NAME
        ,nm.LAST_NAME
        ,nm.FIRST_NAME + ' ' + nm.LAST_NAME fullname
        ,nm.LAST_NAME + ', ' + nm.FIRST_NAME alfaname
        ,acm.AlternateContact
        ,rs.TRM_CDE
        ,rs.YR_CDE
    FROM
        FACULTY_LOAD_TABLE fl with (nolock)
        JOIN
        cte_reg_stu rs with (nolock)
        on (fl.CRS_CDE = rs.CRS_CDE and fl.YR_CDE = rs.YR_CDE and fl.TRM_CDE = rs.TRM_CDE)
        JOIN
        NameMaster nm with (nolock)
        on nm.ID_NUM = fl.INSTRCTR_ID_NUM
        LEFT JOIN
        AlternateContactMethod acm with (nolock)
        on fl.INSTRCTR_ID_NUM = acm.ID_NUM and acm.ADDR_CDE = '*EML'
    WHERE
        fl.YR_CDE = @curyr
        and
        nm.LAST_NAME not like 'TBA %'
    and fl.TRM_CDE = left(@cterm,2)
    -- and fl.CRS_CDE = 'NUR  2000LL'
)

SELECT DISTINCT 
    fac.INSTRCTR_ID_NUM             faculty_unique_id
    ,fac.FIRST_NAME                 faculty_fname
    ,fac.LAST_NAME                  faculty_lname
    ,fac.fullname                   faculty_name
    ,fac.alfaname                   faculty_sortname
    ,fac.AlternateContact           faculty_email
    ,case
        when fac.TRM_CDE = 'FA' then 'Fall '
        when fac.TRM_CDE = 'SP' then 'Spring '
        when fac.TRM_CDE = 'WI' then 'Winter '
        when fac.TRM_CDE = 'SU' then 'Summer '
        else '?'
        end
        + fac.YR_CDE
        + ' Active'                 faculty_semester
    FROM   cte_fac fac
        order BY
            1,2;

    set nocount off;
    REVERT
END

;
GO
/*
with
cte_cal_term as
(
    SELECT
    TOP 3 -- only need this semester and the next 2
        yt.yr_cde,
        yt.trm_cde,
        yt.trm_begin_dte,
        yt.trm_end_dte,
        case
            when TRM_CDE = 'FA' then 'Fall'
            when TRM_CDE = 'WI' then 'Winter'
            when TRM_CDE = 'SP' then 'Spring'
            when TRM_CDE = 'SU' then 'Summer'
        end semester
    FROM
        YEAR_TERM_TABLE yt
    WHERE
        yt.TRM_CDE in ( 'FA','WI','SP','SU' )
        AND
        yt.TRM_END_DTE >= getdate()
    ORDER BY
        yt.TRM_BEGIN_DTE
)
-- select * from cte_cal_term;
,
cte_cal_subterm as
(
    SELECT
        st.yr_cde,
        st.trm_cde,
        st.sbtrm_cde,
        st.sbtrm_begin_dte,
        st.sbtrm_end_dte
    FROM
        YR_TRM_SBTRM_TABLE st -- FIXME the data in J1test only goes to 2024 so far
        JOIN
        cte_cal_term t
            on st.YR_CDE = t.YR_CDE
            and st.TRM_CDE = t.TRM_CDE
)
-- select * from cte_cal_subterm;
 ,
 cte_cal as (
    select
        'course_merrimack_'
            + ct.semester + '_'
            + cast(year(ct.TRM_BEGIN_DTE) as char(4))
	            + (case when cst.SBTRM_CDE is null then '' else '-' + cst.SBTRM_CDE end) + '_'
            + FORMAT(GETDATE(), 'yyyyMMdd') as course_file,
		ct.yr_cde,
		ct.trm_cde,
        cst.sbtrm_cde,
        ct.trm_begin_dte,
        ct.trm_end_dte
    from
        cte_cal_term ct
        left join
        cte_cal_subterm cst
            on ct.YR_CDE=cst.YR_CDE and ct.TRM_CDE=cst.TRM_CDE
 )
 -- select * from cte_cal order by TRM_BEGIN_DTE,TRM_END_DTE
 ,
*/