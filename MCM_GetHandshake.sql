SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[MCM_GetHandshake]
    @exec as bit = 1
WITH EXECUTE AS 'dbo'
AS
-- =============================================
-- Author:		Will Trillich (Serensoft)	
-- Create date: 10/16/2024
-- Description:	Generate symplicity/handshake export
-- Modified:
-- =============================================
BEGIN
    set nocount on;

    declare @cterm as VARCHAR(6) = '2024FA'; -- for debugging
    SET @cterm = dbo.MCM_FN_CALC_TRM('C');
    declare @curyr as INT        = cast(left(@cterm,4) as int);
    declare @nxtyr as INT        = @curyr + 1;
    declare @prvyr as INT        = @curyr - 1;

    declare @nterm as VARCHAR(6) = '2024SP'; -- for debugging
    SET @nterm = dbo.MCM_FN_CALC_TRM('N');
    SET @nterm = right(@nterm,2);

WITH
cteStuCur as (
    --get current registered students
    select DISTINCT sch.ID_NUM, dh.DIV_CDE
    from STUDENT_CRS_HIST sch
        inner join DEGREE_HISTORY dh on sch.ID_NUM = dh.ID_NUM and sch.STUD_DIV = dh.DIV_CDE
    where (sch.YR_CDE = @curyr)
        and sch.TRANSACTION_STS IN ('C', 'H', 'D')
),
cteStuPrev as (
    --get previous term registered students who don't exist in the current student pop
    select DISTINCT sch.ID_NUM, max(dh.DIV_CDE) DIV_CDE --max puts UG first since they can be registered for UG and GR classes at the same time.
    from STUDENT_CRS_HIST sch
        inner join DEGREE_HISTORY dh on sch.ID_NUM = dh.ID_NUM and sch.STUD_DIV = dh.DIV_CDE
        left join cteStuCur on sch.ID_NUM = cteStuCur.ID_NUM
    where (sch.YR_CDE = @prvyr)
        and sch.TRANSACTION_STS IN ('C', 'H', 'D')
        and cteStuCur.ID_NUM is null
    group by sch.ID_NUM
),
cteAdm as (
    --get deposited students for the upcoming term that do not exist in the current term 
    --just in case they switched from UG to GR between current term and next term
	select cand.ID_NUM, cand.DIV_CDE
	from candidacy cand
		inner join AlternateContactMethod acm on cand.ID_NUM = acm.ID_NUM and acm.ADDR_CDE = '*EML'
		left join cteStuCur on cteStuCur.ID_NUM = cand.ID_NUM
	where (cand.YR_CDE = @curyr and cand.TRM_CDE = @nterm
		and cand.CUR_CANDIDACY = 'Y'
		and cand.stage in ('DEPT', 'NMDEP'))
		and acm.AlternateContact like '%@merrimack.edu'
		and cteStuCur.ID_NUM is null
),
cte_Pop as (
	select *
	from cteStuCur
	union all 
	select * 
	from cteStuPrev
	union all
	select *
	from cteAdm
)
-- select * from cte_pop order by ID_NUM;
,

-- ==--==--==--==--==--==--== --

cte_email AS (
    SELECT
        acm.id_num,
        acm.alternatecontact        email,
        LEFT(acm.alternatecontact, Charindex('@', acm.alternatecontact) - 1)
                                    username
    FROM alternatecontactmethod acm WITH (nolock)
    WHERE acm.addr_cde = '*EML'
      AND acm.alternatecontact LIKE '%@merrimack.edu'
      AND acm.ID_NUM in ( select id_num from cte_pop )
)
-- select * from cte_email;
,
cte_bio as (
    SELECT
        nm.ID_NUM,
        nm.FIRST_NAME,
        nm.LAST_NAME,
        nm.MIDDLE_NAME,
        bm.BIRTH_DTE,
        bm.GENDER,
        bm.CITIZEN_OF
    FROM
        NameMaster nm with (nolock)
        join
        BIOGRAPH_MASTER bm with (nolock)
            on nm.ID_NUM = bm.ID_NUM
    WHERE
        nm.ID_NUM in ( select id_num from cte_pop )
)
-- select * from cte_bio;
,
cte_acad as (
    SELECT
        pop.ID_NUM,
        pop.DIV_CDE,
        dh.DIV_CDE      dh_div,
        dh.ENTRY_DTE,
        dh.DEG_APPLICATION_DTE,
        dh.EXPECT_GRAD_TRM,
        dh.EXPECT_GRAD_YR,
        dh.DTE_DEGR_CONFERRED,
        dh.EXIT_REASON                      exit_code,
        td.TABLE_DESC                       exit_descr,
        dh.MAJOR_1                          major1_code,
        maj1.MAJOR_MINOR_DESC               major1_descr,
        dh.MAJOR_2                          major2_code,
        maj2.MAJOR_MINOR_DESC               major2_descr,
        dh.MAJOR_3                          major3_code,
        maj3.MAJOR_MINOR_DESC               major3_descr,
        dh.CONCENTRATION_1                  conc1_code,
        cd1.conc_desc                       conc1_descr,
        dh.CONCENTRATION_2                  conc2_code,
        cd2.conc_desc                       conc2_descr,
        dh.MINOR_1                          minor1_code,
        min1.MAJOR_MINOR_DESC               minor1_descr,
        dh.MINOR_2                          minor2_code,
        min2.MAJOR_MINOR_DESC               minor2_descr,
        dh.MINOR_3                          minor3_code,
        min3.MAJOR_MINOR_DESC               minor3_descr,
        'hmm' x
    FROM
        cte_pop pop
        join
        DEGREE_HISTORY dh
            on (pop.ID_NUM = dh.ID_NUM and pop.DIV_CDE = dh.DIV_CDE)
        LEFT JOIN
        MAJOR_MINOR_DEF maj1 WITH (nolock)
            on ( dh.MAJOR_1 = maj1.MAJOR_CDE )
        LEFT JOIN
        MAJOR_MINOR_DEF maj2 WITH (nolock)
            on ( dh.MAJOR_2 = maj2.MAJOR_CDE )
        LEFT JOIN
        MAJOR_MINOR_DEF maj3 WITH (nolock)
            on ( dh.MAJOR_3 = maj3.MAJOR_CDE )
        LEFT JOIN
        CONCENTRATION_DEF cd1 WITH (nolock)
            on ( dh.concentration_1 = cd1.conc_cde )
        LEFT JOIN
        CONCENTRATION_DEF cd2 WITH (nolock)
            on ( dh.concentration_2 = cd2.conc_cde )
        LEFT JOIN
        MAJOR_MINOR_DEF min1 WITH (nolock)
            on ( dh.MINOR_1 = min1.MAJOR_CDE )
        LEFT JOIN
        MAJOR_MINOR_DEF min2 WITH (nolock)
            on ( dh.MINOR_2 = min2.MAJOR_CDE )
        LEFT JOIN
        MAJOR_MINOR_DEF min3 WITH (nolock)
            on ( dh.MINOR_3 = min3.MAJOR_CDE )
        LEFT JOIN
        TABLE_DETAIL td
            on ( dh.EXIT_REASON = td.TABLE_VALUE and td.COLUMN_NAME = 'exit_reason' )
    WHERE
        dh.CUR_DEGREE = 'Y'
        -- dh.EXPECT_GRAD_TRM not in ('HD','TR') -- FIXME, what's the right way to do this?
        -- students show in multiple rows: andradet@merrimack.edu 377000 for example
)
-- select * from cte_acad where id_num between 377000 and 379000 order by ID_NUM;

select
    email.email,
    pop.ID_NUM              user_name,
    pop.DIV_CDE             prog,
    'FIXME'                 card_id, -- 'swipe'
    bio.FIRST_NAME,
    bio.LAST_NAME,
    bio.MIDDLE_NAME,
    'FIXME'                 school_year_name, -- cl.handshake_text on CX
    'FIXME'                 education_level_name, -- deg.handshake_text on CX
    acad.major1_descr       primary_major_name,
    acad.major2_descr       secondary_major_name,
    -- acad.major3_descr,
    -- acad.conc1_descr        conc1,
    acad.conc1_descr        primary_conc_name,
    -- acad.conc2_descr        conc2,
    acad.conc2_descr        secondary_conc_name,
    acad.minor1_descr       primary_minor_name,
    acad.minor2_descr       secondary_minor_name,
    -- acad.minor3_descr,
    'FIXME'                 college_name, -- subp.handshake_text on CX
    acad.ENTRY_DTE          start_date,
    acad.DTE_DEGR_CONFERRED degree_grant_date,
    acad.EXPECT_GRAD_TRM    plan_grad_sess,
    acad.EXPECT_GRAD_YR     plan_grad_yr,
    bio.CITIZEN_OF          citz2,
    bio.GENDER              gender,
    acad.exit_descr         reason
from
    cte_pop pop
    JOIN
    cte_bio bio
        on pop.ID_NUM = bio.ID_NUM
    JOIN
    cte_email email
        on pop.ID_NUM = email.ID_NUM
    JOIN
    cte_acad acad
        on pop.ID_NUM = acad.ID_NUM
ORDER BY
    pop.ID_NUM
;

    set nocount off;
    REVERT
END

;
GO
