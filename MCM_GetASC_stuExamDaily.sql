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
		JOB_TIME
    FROM
        STUDENT_CRS_HIST sch with (nolock)
    WHERE
        ID_NUM in ( SELECT ID_NUM FROM cte_pop )
        and CRS_CDE like 'FYE%1050%' 
)
-- select * from cte_fye;
,
--cte_exam_detail as (
--    SELECT
--        t.ID_NUM,
--        t.TST_CDE,
--        -- t.TST_SEQ,
--		d.TST_SCORE TOTAL_COMPOS_SCORE, 
--        --t.TOTAL_COMPOS_SCORE,
--        d.TST_ELEM,
--        t.DTE_TAKEN, 
--		t.JOB_TIME ts_job_time, 
--		d.JOB_TIME tsd_job_time
--    FROM
--        TEST_SCORES t  with (nolock)
--        JOIN
--        TEST_SCORES_DETAIL d with (nolock)
--            on (t.id_num=d.id_num and t.tst_cde=d.tst_cde and t.tst_seq=d.tst_seq)
--    WHERE
--        t.ID_NUM in ( select ID_NUM from cte_pop )
--        and t.TST_CDE in ( 'MPE','SPA','ITA','FRE' )
--        and d.TST_ELEM in ('PART1','MPE','MPER','SPA','SPAR','ITA','ITAR','FRE','FRER')
--        -- and t.TOTAL_COMPOS_SCORE > 0
--)
---- select * from cte_exam_detail;
--,
--cte_exams as (
--    SELECT
--        ID_NUM,
--        max(case when tst_cde='MPE' then 'MPE' else null end) MPE_TEST,
--        max(case when tst_cde='MPE' and tst_elem='PART1' then TOTAL_COMPOS_SCORE else null end) MPE_SCORE,
--        max(case when tst_cde='MPE' and tst_elem='MPE'   then TOTAL_COMPOS_SCORE else null end) MPE_TOTAL,
--        max(case when tst_cde='MPE' and tst_elem='MPER'  then TOTAL_COMPOS_SCORE else null end) MPE_COURSE,
--        max(case when tst_cde='MPE'                      then DTE_TAKEN          else null end) MPE_UPLOAD_DATE,
--        max(case when tst_cde='SPA' then 'SPA' else null end) SPA_TEST,
--        max(case when tst_cde='SPA' and tst_elem='SPA'   then TOTAL_COMPOS_SCORE else null end) SPA_SCORE,
--        max(case when tst_cde='SPA' and tst_elem='SPAR'  then TOTAL_COMPOS_SCORE else null end) SPA_COURSE,
--        max(case when tst_cde='SPA'                      then DTE_TAKEN          else null end) SPA_UPLOAD_DATE,
--        max(case when tst_cde='ITA' then 'ITA' else null end) ITA_TEST,
--        max(case when tst_cde='ITA' and tst_elem='ITA'   then TOTAL_COMPOS_SCORE else null end) ITA_SCORE,
--        max(case when tst_cde='ITA' and tst_elem='ITAR'  then TOTAL_COMPOS_SCORE else null end) ITA_COURSE,
--        max(case when tst_cde='ITA'                      then DTE_TAKEN          else null end) ITA_UPLOAD_DATE,
--        max(case when tst_cde='FRE' then 'FRE' else null end) FRA_TEST,
--        max(case when tst_cde='FRE' and tst_elem='FRE'   then TOTAL_COMPOS_SCORE else null end) FRA_SCORE,
--        max(case when tst_cde='FRE' and tst_elem='FRER'  then TOTAL_COMPOS_SCORE else null end) FRA_COURSE,
--        max(case when tst_cde='FRE'                      then DTE_TAKEN          else null end) FRA_UPLOAD_DATE, 
--		max(ts_job_time) ts_job_time, 
--		max(tsd_job_time) tsd_job_time
--    FROM
--        cte_exam_detail
--    GROUP BY
--        ID_NUM
--),
-- select * from cte_exams where FRE_TEST > '!';
cte_exams as (
	SELECT ID_NUM, MAX(FRE) FRA_SCORE, MAX(FRER) FRA_COURSE, MAX(DTE_TAKEN) FRA_UPLOAD_DATE, 
		MAX(ITA) ITA_SCORE, MAX(ITAR) ITA_COURSE, MAX(DTE_TAKEN) ITA_UPLOAD_DATE,
		MAX(SPA) SPA_SCORE, MAX(SPAR) SPA_COURSE, MAX(DTE_TAKEN) SPA_UPLOAD_DATE,
		MAX(PART1) MPE_SCORE, MAX(MCOMP) MPE_TOTAL, MAX(MPER) MPE_COURSE, MAX(DTE_TAKEN) MPE_UPLOAD_DATE, MAX(job_time) JOB_TIME
	FROM (
			SELECT ts.ID_NUM, ts.DTE_TAKEN, tsd.TST_ELEM, tsd.TST_SCORE, ts.JOB_TIME
			FROM TEST_SCORES ts WITH (NOLOCK)
				inner join TEST_SCORES_DETAIL tsd WITH (NOLOCK) on ts.ID_NUM = tsd.ID_NUM and ts.tst_cde=tsd.tst_cde and ts.tst_seq=tsd.tst_seq
			WHERE tsd.TST_ELEM IN ('FRE', 'FRER', 'ITA', 'ITAR', 'SPA', 'SPAR', 'MCOMP', 'MPER', 'PART1') 
				AND ts.ID_NUM IN ( select ID_NUM from cte_pop )
		) d
		PIVOT
		(
			MAX(TST_SCORE)
			FOR TST_ELEM IN (FRE, FRER, ITA, ITAR, SPA, SPAR, MCOMP, MPER, PART1) 
		) piv
	GROUP BY ID_NUM
),

cteAll as (
	SELECT
		s.SCON          slate_guid,
		p.ID_NUM        mc_id,
		case when f.ID_NUM > 0 then 'Y' else 'N' end
						fye_attended,
		CASE WHEN x.MPE_SCORE is not null THEN 'MPE' ELSE NULL END mpe_test,
		x.mpe_score,
		x.mpe_total,
		x.mpe_course,
		CASE WHEN x.MPE_SCORE is not null THEN x.MPE_UPLOAD_DATE ELSE NULL END mpe_upload_date,
		CASE WHEN x.SPA_SCORE is not null THEN 'SPA' ELSE NULL END spa_test,
		x.spa_score,
		x.spa_course,
		CASE WHEN x.SPA_SCORE is not null THEN x.SPA_UPLOAD_DATE ELSE NULL END spa_upload_date,
		CASE WHEN x.ITA_SCORE is not null THEN 'ITA' ELSE NULL END ita_test,
		x.ita_score,
		x.ita_course,
		CASE WHEN x.ITA_SCORE is not null THEN x.ITA_UPLOAD_DATE ELSE NULL END ita_upload_date,
		CASE WHEN x.FRA_SCORE is not null THEN 'FRA' ELSE NULL END fra_test,
		x.fra_score,
		x.fra_course,
		CASE WHEN x.FRA_SCORE is not null THEN x.FRA_UPLOAD_DATE ELSE NULL END fra_upload_date, 
		(SELECT MAX (v) FROM (VALUES (s.JOB_TIME), (x.JOB_TIME), (f.JOB_TIME)) AS value(v)) as JOB_TIME
	FROM
		cte_pop p
		JOIN
		cte_exams x on (p.ID_NUM = x.ID_NUM)
		LEFT JOIN
		cte_fye f on (x.ID_NUM = f.ID_NUM)
		LEFT JOIN
		cte_slateids s on (x.ID_NUM = s.ID_NUM)
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
