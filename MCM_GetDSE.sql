SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[MCM_GetDSE]
    @exec as bit = 1
WITH EXECUTE AS 'dbo'
AS
-- =============================================
-- Author:		Will Trillich (Serensoft)	
-- Create date: 10/16/2024
-- Description:	Generate DSErec export
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
    select DISTINCT sch.ID_NUM
    from
        STUDENT_CRS_HIST sch with (nolock)
        inner join
        DEGREE_HISTORY dh with (nolock)
            on sch.ID_NUM = dh.ID_NUM and sch.STUD_DIV = dh.DIV_CDE
    where (sch.YR_CDE = @curyr)
        and sch.TRANSACTION_STS IN ('C', 'H', 'D')
)
,
cteAdm as (
    --get deposited students for the upcoming term that do not exist in the current term 
    --just in case they switched from UG to GR between current term and next term
	select cand.ID_NUM
	from
        candidacy cand with (nolock)
        inner join
        AlternateContactMethod acm with (nolock)
            on cand.ID_NUM = acm.ID_NUM and acm.ADDR_CDE = '*EML'
		left join
            cteStuCur on cteStuCur.ID_NUM = cand.ID_NUM
	where (cand.YR_CDE = @curyr and cand.TRM_CDE = @nterm
		and cand.CUR_CANDIDACY = 'Y'
		and cand.stage in ('DEPT', 'NMDEP'))
		and acm.AlternateContact like '%@merrimack.edu'
		and cteStuCur.ID_NUM is null
)
,
cteEmpl as (
    -- current employees
    SELECT DISTINCT
        ID_NUM
    FROM
        EMPL_MAST emp with (nolock) -- FIXME is this the canonical place for employees?
    WHERE
        emp.TERMINATION_DTE is null or emp.TERMINATION_DTE > getdate()
)
,
cteOPT as (
    -- optional practice training OPT students
    --  or fitness center FITA folks
    SELECT
        ID_NUM,
        ATTRIB_CDE,
        ATTRIB_END_DATE
    FROM
        ATTRIBUTE_TRANS attr with (nolock)
    WHERE
        attr.ATTRIB_CDE in ( 'OPT','FITA' ) -- FIXME wild ass guess here
        and
        (attr.ATTRIB_END_DATE is null or attr.ATTRIB_END_DATE > getdate())
)
,
cte_Pop as (
	SELECT ID_NUM
	FROM cteStuCur
	UNION
    SELECT ID_NUM
    FROM cteEmpl
    UNION
	SELECT ID_NUM
	FROM cteAdm
    UNION
    SELECT ID_NUM
    FROM cteOPT
)
-- select * from cte_pop order by ID_NUM;
,

-- ==--==--==--==--==--==--== --

cte_email AS (
    SELECT
        acm.id_num,
        acm.StartDate               beg_date,
        acm.EndDate                 end_date,
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
        bm.GENDER
    FROM
        NameMaster nm with (nolock)
        JOIN
        BIOGRAPH_MASTER bm with (nolock)
            on nm.ID_NUM = bm.ID_NUM
    WHERE
        nm.ID_NUM in ( select id_num from cte_pop )
)
-- select * from cte_bio;
,
cte_acad as (
    SELECT
        ID_NUM,
        EXPECT_GRAD_YR,
        EXIT_DTE
    FROM
        DEGREE_HISTORY dh with (nolock)
    WHERE
        dh.ID_NUM in ( select id_num from cte_pop )
        and
        dh.CUR_DEGREE = 'Y'
)

select
    bio.FIRST_NAME              firstname,
    bio.LAST_NAME               lastname,
    email.email                 merrimack_email,
    email.beg_date,
    'FIXME'                     card_swipe,
    pop.ID_NUM                  merrimack_id,
    pop.ID_NUM                  unique_id,
    email.username              user_name,
    case
        when pop.ID_NUM in (
            SELECT
                ID_NUM
            FROM
                ATTRIBUTE_TRANS attr with (nolock)
            WHERE
                attr.ATTRIB_CDE in ( 'FITD' ) -- FIXME wild ass guess here
                and
                (attr.ATTRIB_END_DATE is null or attr.ATTRIB_END_DATE > getdate())
        )
        then 'denied'
        when pop.ID_NUM in (
            select ID_NUM
            from cteEmpl
            -- CX: where involvement code NOT in FAC|ADJ|GADJ|EADJ|REML|MEML FIXME
        )
        then 'staff'
        when pop.ID_NUM in (
            select ID_NUM
            from cteEmpl
            -- CX: where involvement code in FAC|ADJ|GADJ|EADJ|REML|MEML FIXME
        )
        then 'faculty'
        when pop.ID_NUM in (
            select ID_NUM
            from cte_acad
            where EXIT_DTE is null or EXIT_DTE > getdate()
                UNION
            select ID_NUM
            from cteOPT
            where ATTRIB_CDE='OPT' and (ATTRIB_END_DATE is null or ATTRIB_END_DATE > getdate())
        )
        then 'student'
        when pop.ID_NUM in (
            select ID_NUM
            from cteOPT
            where ATTRIB_CDE='FITA' and (ATTRIB_END_DATE is null or ATTRIB_END_DATE > getdate())
        )
        then 'other'
        else '?'
        END                     affiliation,
    bio.GENDER                  gender,
    acad.EXPECT_GRAD_YR         class_year

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