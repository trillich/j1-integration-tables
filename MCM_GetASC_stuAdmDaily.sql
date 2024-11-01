SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[MCM_GetASC_stuAdmDaily]
   @lastpull as datetime

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

WITH
cte_can as (
    SELECT
        c.ID_NUM            mc_id,
		cu.Slate_AppID,
        c.TRM_CDE           plan_enr_sess,
        c.YR_CDE            plan_enr_yr,
        c.DIV_CDE           adm_prog,
        c.PROG_CDE          adm_major,
        c.STAGE             adm_enrstat, 
        'FULL'              adm_decsn_code, -- FIXME
        h.hist_stage_dte    adm_decsn_date,
        concat(c.TRM_CDE,' ',cast(c.YR_CDE as char(4)))
                            adm_plansessyr, 
		c.JOB_TIME
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
		LEFT JOIN CANDIDACY_UDF cu WITH (NOLOCK) on c.ID_NUM = cu.ID_NUM AND c.YR_CDE = cu.YR_CDE
			AND c.TRM_CDE = cu.TRM_CDE AND c.DIV_CDE = cu.DIV_CDE and c.PROG_CDE = cu.PROG_CDE
    WHERE (
			(c.div_cde = 'UG' AND c.TRM_CDE + c.YR_CDE IN 
				(SELECT term + [YEAR] 
				 FROM MCM_div_process WITH (NOLOCK) 
				 WHERE division = 'UG' AND process = 'MCConnectADM' AND CAST(getdate() as date) BETWEEN active_date AND inactive_date )
				)
			OR 
		   (c.div_cde = 'GR' AND c.TRM_CDE + c.YR_CDE IN 
			   (SELECT term + [YEAR] 
				FROM MCM_div_process WITH (NOLOCK) 
				WHERE division = 'GR' AND process = 'MCConnectADM' AND CAST(getdate() as date) BETWEEN active_date AND inactive_date )
			   )
		  )
        AND c.STAGE IN ( 'DEPT', 'NMDEP' )
        AND c.CUR_CANDIDACY = 'Y'
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
            nm.SUFFIX               suffix_name,
			nm.JOB_TIME
        FROM
            NameMaster nm WITH (nolock)
        WHERE
            ID_NUM in ( select mc_id from cte_can )
    )
-- select * from cte_names where suffix>'!';
    ,
cte_bio
    as (
        SELECT
            bm.ID_NUM,
            -- bm.GENDER           Sex,
            format(bm.birth_dte, 'M/d/yyyy') birthday, 
			bm.JOB_TIME
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
            bm.id_num in (select mc_id from cte_can)
    )
-- select * from cte_bio where race='Hispanic';
    ,
cte_email
     AS (SELECT id_num,
                -- LEFT(acm.alternatecontact, 
                --     Charindex('@', acm.alternatecontact) - 1)
                --                         username,
                acm.alternatecontact    email, 
				acm.ChangeTime JOB_TIME
         FROM   alternatecontactmethod acm WITH (nolock)
         WHERE  acm.addr_cde = '*EML'
                AND acm.alternatecontact LIKE '%@merrimack.edu'
                AND id_num in ( select mc_id from cte_can )
    )
-- select * from cte_email;
,
cte_slateids as (
    SELECT
        ai.ID_NUM,
        can.adm_prog, -- div_cde
		case when IDENTIFIER_TYPE='SUG' then IDENTIFIER else null end SUG,
		case when IDENTIFIER_TYPE='SGP' then IDENTIFIER else null end SGPS,
		case when IDENTIFIER_TYPE='SCON' then IDENTIFIER else null end SCON,
		ISNULL(can.Slate_AppID, '') Slate_AppID, 
		ai.JOB_TIME
    FROM
        ALTERNATE_IDENTIFIER ai WITH (nolock)
        JOIN
        cte_can can
            on ai.ID_NUM = can.mc_id
    WHERE
        ai.IDENTIFIER_TYPE in ('SUG','SGP', 'SCON')
        and (ai.BEGIN_DTE is null or ai.BEGIN_DTE <= getdate())
        and (ai.END_DTE is null or ai.END_DTE > getdate())
),
cteAll as (
	SELECT
		slt.SCON slate_id,
		case
			when slt.adm_prog='GR' then slt.SGPS
			when slt.adm_prog='UG' then slt.SUG
			else ''
		end                 slate_guid, -- person guid based on program
		can.Slate_AppID             slate_appid, 
		mc_id,
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
		can.adm_decsn_date, 
		(SELECT MAX (v) FROM (VALUES (can.JOB_TIME), (names.JOB_TIME), (bio.JOB_TIME), (email.JOB_TIME), (slt.JOB_TIME)) AS value(v)) as JOB_TIME
	FROM
		cte_can can
		JOIN
		cte_names names
			on ( can.mc_id = names.ID_NUM )
		LEFT JOIN
		cte_bio bio
			on ( can.mc_id = bio.ID_NUM )
		LEFT JOIN
		cte_email email
			on ( can.mc_id = email.ID_NUM )
		LEFT JOIN
		cte_slateids slt
			on ( can.mc_id = slt.ID_NUM )
)
SELECT * 
FROM cteAll
WHERE cteAll.JOB_TIME >= @lastpull
ORDER BY cteAll.mc_id
    ;

    set nocount off;
    REVERT
END

;
GO
