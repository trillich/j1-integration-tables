SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[MCM_GetBBAcourseFile](
    @daysago int
)

WITH EXECUTE AS 'dbo'
AS
-- =============================================
-- Author:		Will Trillich (Serensoft)	
-- Create date: 1/28/2025
-- Description:	Generate BBA Bookstore COURSES filenames for 3 semesters
-- Modified:	

-- =============================================
BEGIN

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
            YEAR_TERM_TABLE yt with (nolock)
        WHERE
            yt.TRM_CDE in ( 'FA','WI','SP','SU' )
            AND
            yt.TRM_END_DTE >= getdate() - @daysago
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
            YR_TRM_SBTRM_TABLE st with (nolock) -- FIXME the data in J1test only goes to 2024 so far
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
    select * from cte_cal order by TRM_BEGIN_DTE,TRM_END_DTE

    set nocount off;
    REVERT
END

;
GO

exec MCM_GetBBAcourseFile 0 ;