SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[MCM_GetASC_stuExamDaily]
     @lastpull as datetime
WITH EXECUTE AS 'dbo'
AS
-- =============================================
-- Author:		Will Trillich (Serensoft)	
-- Create date: 10/8/2024
-- Description:	Generate ASC exam export for slate
-- Modified:	
-- =============================================
BEGIN
     set nocount on;

        declare @cterm as VARCHAR(6) = '2024FA'; -- for debugging
        set @cterm = dbo.MCM_FN_CALC_TRM('C');
        declare @curyr as INT        = cast(left(@cterm,4) as int);

-- [JZMCM-SQL].[J1TEST].[dbo]. <== table prefix for LIVE-ish database
-- select count(*) from namemaster;
-- select count(*) from [JZMCM-SQL].[J1TEST].[dbo].namemaster;

WITH
cte_pop as (
	--Just retrieve the unique population of ID's that match the current academic year
	SELECT DISTINCT
            sm.ID_NUM,
            dh.DIV_CDE
	 FROM
            STUDENT_MASTER sm WITH (nolock)
            JOIN
            DEGREE_HISTORY dh WITH (nolock)
                on sm.ID_NUM = dh.ID_NUM
	 WHERE sm.id_num in (
                SELECT distinct id_num
                FROM STUDENT_CRS_HIST sch
                WHERE stud_div IN ( 'UG', 'GR' )
                AND sch.YR_CDE in (@curyr)
                AND sch.transaction_sts IN ( 'H', 'C', 'D' )
        )
            AND sm.CURRENT_CLASS_CDE NOT IN ( 'CE','NM','AV' )
            AND dh.MAJOR_1 <> 'NOM' -- omit nonmatric
            AND dh.cur_degree = 'Y'
)
,
cte_slateids as (
    SELECT
        ID_NUM,
        IDENTIFIER as SCON, 
		JOB_TIME
    FROM
        ALTERNATE_IDENTIFIER ai
    WHERE
        ai.ID_NUM in ( select ID_NUM from cte_pop )
        and ai.IDENTIFIER_TYPE = 'SCON' 
        and (ai.BEGIN_DTE is null or ai.BEGIN_DTE <= getdate())
        and (ai.END_DTE is null or ai.END_DTE > getdate())
)

,
cte_fye as (
    SELECT 
        ID_NUM, 
		max(JOB_TIME) JOB_TIME
    FROM
        STUDENT_CRS_HIST sch with (nolock)
    WHERE
        ID_NUM in ( select ID_NUM from cte_pop )
        and CRS_CDE like 'FYE%1050%' 
	GROUP BY ID_NUM
)
,
cte_fr as (
	SELECT ID_NUM, MAX(APPID) APPID, MAX(FRE) FRA_SCORE, MAX(FRER) FRA_COURSE, MAX(DTE_TAKEN) FRA_UPLOAD_DATE, MAX(job_time) JOB_TIME
	FROM (
			SELECT ts.ID_NUM, ts.APPID, ts.DTE_TAKEN, tsd.TST_ELEM, tsd.TST_SCORE, ts.JOB_TIME
			FROM TEST_SCORES ts WITH (NOLOCK)
				inner join TEST_SCORES_DETAIL tsd WITH (NOLOCK) on ts.ID_NUM = tsd.ID_NUM and ts.tst_cde=tsd.tst_cde and ts.tst_seq=tsd.tst_seq
			WHERE tsd.TST_ELEM IN ('FRE', 'FRER') 
				AND ts.ID_NUM IN ( select ID_NUM from cte_pop )
		) d
		PIVOT
		(
			MAX(TST_SCORE)
			FOR TST_ELEM IN (FRE, FRER) 
		) piv
	GROUP BY ID_NUM, APPID
),
cte_sp as (
	SELECT ID_NUM, MAX(APPID) APPID, MAX(SPA) SPA_SCORE, MAX(SPAR) SPA_COURSE, MAX(DTE_TAKEN) SPA_UPLOAD_DATE, MAX(job_time) JOB_TIME
	FROM (
			SELECT ts.ID_NUM, ts.APPID, ts.DTE_TAKEN, tsd.TST_ELEM, tsd.TST_SCORE, ts.JOB_TIME
			FROM TEST_SCORES ts WITH (NOLOCK)
				inner join TEST_SCORES_DETAIL tsd WITH (NOLOCK) on ts.ID_NUM = tsd.ID_NUM and ts.tst_cde=tsd.tst_cde and ts.tst_seq=tsd.tst_seq
			WHERE tsd.TST_ELEM IN ('SPA', 'SPAR') 
				AND ts.ID_NUM IN ( select ID_NUM from cte_pop )
		) d
		PIVOT
		(
			MAX(TST_SCORE)
			FOR TST_ELEM IN (SPA, SPAR) 
		) piv
	GROUP BY ID_NUM
),
cte_it as (
	SELECT ID_NUM, MAX(APPID) APPID, MAX(ITA) ITA_SCORE, MAX(ITAR) ITA_COURSE, MAX(DTE_TAKEN) ITA_UPLOAD_DATE, MAX(job_time) JOB_TIME
	FROM (
			SELECT ts.ID_NUM, ts.APPID, ts.DTE_TAKEN, tsd.TST_ELEM, tsd.TST_SCORE, ts.JOB_TIME
			FROM TEST_SCORES ts WITH (NOLOCK)
				inner join TEST_SCORES_DETAIL tsd WITH (NOLOCK) on ts.ID_NUM = tsd.ID_NUM and ts.tst_cde=tsd.tst_cde and ts.tst_seq=tsd.tst_seq
			WHERE tsd.TST_ELEM IN ('ITA', 'ITAR') 
				AND ts.ID_NUM IN ( select ID_NUM from cte_pop )
		) d
		PIVOT
		(
			MAX(TST_SCORE)
			FOR TST_ELEM IN (ITA, ITAR) 
		) piv
	GROUP BY ID_NUM
),
cte_mpe as (
	SELECT ID_NUM, MAX(APPID) APPID, MAX(PART1) MPE_SCORE, MAX(MCOMP) MPE_TOTAL, MAX(MPER) MPE_COURSE, MAX(DTE_TAKEN) MPE_UPLOAD_DATE, MAX(job_time) JOB_TIME
	FROM (
			SELECT ts.ID_NUM, ts.APPID, ts.DTE_TAKEN, tsd.TST_ELEM, tsd.TST_SCORE, ts.JOB_TIME
			FROM TEST_SCORES ts WITH (NOLOCK)
				inner join TEST_SCORES_DETAIL tsd WITH (NOLOCK) on ts.ID_NUM = tsd.ID_NUM and ts.tst_cde=tsd.tst_cde and ts.tst_seq=tsd.tst_seq
			WHERE tsd.TST_ELEM IN ('MCOMP', 'MPER', 'PART1') 
				AND ts.ID_NUM IN ( select ID_NUM from cte_pop )
		) d
		PIVOT
		(
			MAX(TST_SCORE)
			FOR TST_ELEM IN (MCOMP, MPER, PART1) 
		) piv
	GROUP BY ID_NUM
),

cteAll as (
	SELECT
		--s.SCON          slate_guid,
		p.ID_NUM        mc_id,
		--case when f.ID_NUM > 0 then 'Y' else 'N' end
		--				fye_attended,
		mpe.APPID as mpe_appid,
		CASE WHEN mpe.MPE_SCORE is not null THEN 'MPE' ELSE NULL END mpe_test,
		mpe.mpe_score,
		mpe.mpe_total,
		mpe.mpe_course,
		CASE WHEN mpe.MPE_SCORE is not null THEN mpe.MPE_UPLOAD_DATE ELSE NULL END mpe_upload_date,
		sp.APPID as sp_appid,
		CASE WHEN sp.SPA_SCORE is not null THEN 'SPA' ELSE NULL END spa_test,
		sp.spa_score,
		sp.spa_course,
		CASE WHEN sp.SPA_SCORE is not null THEN sp.SPA_UPLOAD_DATE ELSE NULL END spa_upload_date,
		it.APPID as it_appid,
		CASE WHEN it.ITA_SCORE is not null THEN 'ITA' ELSE NULL END ita_test,
		it.ita_score,
		it.ita_course,
		CASE WHEN it.ITA_SCORE is not null THEN it.ITA_UPLOAD_DATE ELSE NULL END ita_upload_date,
		fr.APPID as fr_appid,
		CASE WHEN fr.FRA_SCORE is not null THEN 'FRA' ELSE NULL END fra_test,
		fr.fra_score,
		fr.fra_course,
		CASE WHEN fr.FRA_SCORE is not null THEN fr.FRA_UPLOAD_DATE ELSE NULL END fra_upload_date,
		(SELECT MAX (v) FROM (VALUES (s.JOB_TIME), (fr.JOB_TIME), (sp.JOB_TIME), (it.JOB_TIME), (mpe.JOB_TIME), (f.JOB_TIME)) AS value(v)) as JOB_TIME
	FROM
		cte_pop p
		LEFT JOIN cte_fr fr on (p.ID_NUM = fr.ID_NUM)
		LEFT JOIN cte_sp sp on (p.ID_NUM = sp.ID_NUM) 
		LEFT JOIN cte_it it on (p.ID_NUM = it.ID_NUM) 
		LEFT JOIN cte_mpe mpe on (p.ID_NUM = mpe.ID_NUM) 
		LEFT JOIN cte_fye f on (p.ID_NUM = f.ID_NUM)
		LEFT JOIN cte_slateids s on (p.ID_NUM = s.ID_NUM)
	WHERE (fr.ID_NUM IS NOT NULL AND sp.ID_NUM IS NOT NULL AND it.ID_NUM IS NOT NULL AND MPE.ID_NUM IS NOT NULL AND f.ID_NUM IS NOT NULL)
)
SELECT *
FROM cteAll
WHERE cteAll.JOB_TIME >= @lastpull
;

    set nocount off;
    REVERT
END

;
GO
