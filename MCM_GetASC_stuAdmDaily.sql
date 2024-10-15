SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[MCM_GetASC_stuAdmDaily]
    @exec as bit = 1
WITH EXECUTE AS 'dbo'
AS
-- =============================================
-- Author:		Will Trillich (Serensoft)	
-- Create date: 9/28/2024
-- Description:	Generate ASC/connect export 1of10: stuAdmDaily
-- Modified:
-- =============================================
BEGIN
     set nocount on;

    declare @cterm as VARCHAR(6) = '2024FA'; -- for debugging
    SET @cterm = dbo.MCM_FN_CALC_TRM('C');
    declare @curyr as INT        = cast(left(@cterm,4) as int);

    SET @cterm = right(@cterm,2);

WITH
cte_can as (
    SELECT
        c.ID_NUM            cx_id,
        c.TRM_CDE           plan_enr_sess,
        c.YR_CDE            plan_enr_yr,
        c.DIV_CDE           adm_prog,
        c.PROG_CDE          adm_major,
        c.STAGE             adm_enrstat, -- FIXME just guessing here
        'FULL'              adm_decsn_code, -- FIXME
        h.hist_stage_dte    adm_decsn_date,
        concat(c.TRM_CDE,' ',cast(c.YR_CDE as char(4)))
                            adm_plansessyr
    FROM
        candidacy c with (nolock)
        LEFT JOIN
        stage_history_tran h with (nolock)
            on (c.ID_NUM = h.ID_NUM
            and c.YR_CDE = h.YR_CDE
            and c.TRM_CDE = h.TRM_CDE
            and c.PROG_CDE = h.PROG_CDE
            and c.DIV_CDE = h.DIV_CDE
            and h.hist_stage='ACPT' )
    WHERE   c.div_cde IN ( 'UG', 'GR' )
        AND c.YR_CDE = @curyr
        AND c.TRM_CDE = @cterm
        AND c.STAGE IN ( 'DEPT', 'NMDEP' )
        AND c.CUR_CANDIDACY = 'Y'
        /*
        on CX we used a custom table slateasc_process_table
        which used today's date to determine which semesters
        were 'active'.
        SP2025 & WI2025 for CE/UNDG/GRAD would be active starting 10/31/2024
        SU2024 was the only session active for CE/UNDG/GRAD up til 9/1/2024
        */
)
-- select * from cte_can order by cx_id;
,

cte_names
    as (
        SELECT
            nm.ID_NUM,
            nm.FIRST_NAME           first_name,
            nm.FIRST_NAME           pref_first_name, -- FIXME...?
            nm.LAST_NAME            last_name,
            nm.MIDDLE_NAME          middle_name,
            nm.SUFFIX               suffix_name
        FROM
            NameMaster nm WITH (nolock)
        WHERE
            ID_NUM in ( select cx_id from cte_can )
    )
-- select * from cte_names where suffix>'!';
    ,
cte_bio
    as (
        SELECT
            bm.ID_NUM,
            -- bm.GENDER           Sex,
            format(bm.birth_dte, 'M/d/yyyy') birthday
            -- ethnic.IPEDS_Desc   Ethnicity,
            -- CASE
            --     WHEN ethnic.ethnic_rpt_def_num = -1
            --     THEN 'Hispanic'
            --     ELSE ethnic.IPEDS_Desc
            --     END             Race,
            -- case 
            --     WHEN CITIZEN_OF <> 'US'
            --     THEN 'True'
            --     WHEN CITIZEN_OF is NULL
            --     then 'True'
            --     else 'False'
            --     END             International
        FROM
            BIOGRAPH_MASTER bm WITH (nolock)
            -- LEFT JOIN
            -- mcm_latest_ethnicrace_detail ethnic WITH (nolock)
            --     ON ( bm.id_num = ethnic.id_num )
        WHERE
            bm.id_num in (select cx_id from cte_can)
    )
-- select * from cte_bio where race='Hispanic';
    ,
cte_email
     AS (SELECT id_num,
                -- LEFT(acm.alternatecontact, 
                --     Charindex('@', acm.alternatecontact) - 1)
                --                         username,
                acm.alternatecontact    email
         FROM   alternatecontactmethod acm WITH (nolock)
         WHERE  acm.addr_cde = '*EML'
                AND acm.alternatecontact LIKE '%@merrimack.edu'
                AND id_num in ( select cx_id from cte_can )
    )
-- select * from cte_email;
,
cte_slateids as (
    SELECT
        ai.ID_NUM,
        can.adm_prog, -- div_cde
        max(case when IDENTIFIER_TYPE='SUG' then IDENTIFIER else null end) SUG,
        max(case when IDENTIFIER_TYPE='SGPS' then IDENTIFIER else null end) SGPS
    FROM
        ALTERNATE_IDENTIFIER ai WITH (nolock)
        JOIN
        cte_can can
            on ai.ID_NUM = can.cx_id
    WHERE
        ai.IDENTIFIER_TYPE in ('SUG','SGPS')
        and (ai.BEGIN_DTE is null or ai.BEGIN_DTE <= getdate())
        and (ai.END_DTE is null or ai.END_DTE > getdate())
    GROUP BY ai.ID_NUM, can.adm_prog
)

SELECT

    slt.SUG                         slate_id,
    slt.SGPS                        slate_guid_asc,
    cx_id,
    first_name,
    pref_first_name,
    last_name,
    middle_name,
    suffix_name,
    email,
    birthday,
    adm_plansessyr,
    can.adm_prog,
    can.adm_major,
    can.adm_enrstat,
    can.adm_decsn_code,
    can.adm_decsn_date
FROM
    cte_can can
    JOIN
    cte_names names
        on ( can.cx_id = names.ID_NUM )
    LEFT JOIN
    cte_bio bio
        on ( can.cx_id = bio.ID_NUM )
    LEFT JOIN
    cte_email email
        on ( can.cx_id = email.ID_NUM )
    LEFT JOIN
    cte_slateids slt
        on ( can.cx_id = slt.ID_NUM )
ORDER BY
    cx_id
    ;

    set nocount off;
    REVERT
END

;
GO
