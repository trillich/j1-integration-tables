SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[MCM_GetASC_stuExamDaily]
    @exec as bit = 1
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
        -- declare @nxtyr as INT        = @curyr + 1;
        -- declare @prvyr as INT        = @curyr - 1;

        -- declare @pterm as VARCHAR(6) = '2023SP'; -- for debugging
        -- set @pterm = dbo.MCM_FN_CALC_TRM('P');
        -- declare @pyr   as INT        = cast(left(@pterm,4) as int);

        -- print @cterm +'/'+ cast(@curyr as varchar)

        -- SET @cterm = right(@cterm,2);
        -- print concat('cterm=',@cterm,', yrs=[',@prvyr,',',@curyr,',',@nxtyr,']: pterm=',@pterm);
        -- SET @pterm = right(@pterm,2);

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
            AND dh.MAJOR_1 <> 'GEN' -- omit nonmatric
            AND dh.cur_degree = 'Y'
)
,
cte_slateids as (
    SELECT
        ID_NUM,
        max(case when IDENTIFIER_TYPE='SUG' then IDENTIFIER else null end) SUG,
        max(case when IDENTIFIER_TYPE='SGPS' then IDENTIFIER else null end) SGPS
    FROM
        ALTERNATE_IDENTIFIER ai
    WHERE
        ai.ID_NUM in ( select ID_NUM from cte_pop )
        and ai.IDENTIFIER_TYPE in ('SUG','SGPS') -- FIXME no SGPS data in J1CONV, need to confirm with real data
        and (ai.BEGIN_DTE is null or ai.BEGIN_DTE <= getdate())
        and (ai.END_DTE is null or ai.END_DTE > getdate())
    GROUP BY ID_NUM
)
-- select * from cte_slateids where sgps > '!';
,
cte_fye as (
    SELECT
        ID_NUM
    FROM
        STUDENT_CRS_HIST sch
    WHERE
        ID_NUM in ( SELECT ID_NUM FROM cte_pop )
        and CRS_CDE like 'FYE%1050%' -- FIXME is this the right pattern?
)
-- select * from cte_fye;
,
cte_exam_detail as (
    SELECT
        t.ID_NUM,
        t.TST_CDE,
        -- t.TST_SEQ,
        t.TOTAL_COMPOS_SCORE,
        d.TST_ELEM,
        t.DTE_TAKEN
    FROM
        TEST_SCORES t JOIN
        TEST_SCORES_DETAIL d
            on (t.id_num=d.id_num and t.tst_cde=d.tst_cde and t.tst_seq=d.tst_seq)
    WHERE
        t.ID_NUM in ( select ID_NUM from cte_pop )
        and t.TST_CDE in ( 'MPE','SPA','ITA','FRE' )
        and d.TST_ELEM in ('PART1','MPE','MPER','SPA','SPAR','ITA','ITAR','FRE','FRER')
        -- and t.TOTAL_COMPOS_SCORE > 0
)
-- select * from cte_exam_detail;
,
cte_exams as (
    SELECT
        ID_NUM,
        max(case when tst_cde='MPE' then 'MPE' else null end) MPE_TEST,
        max(case when tst_cde='MPE' and tst_elem='PART1' then TOTAL_COMPOS_SCORE else null end) MPE_SCORE,
        max(case when tst_cde='MPE' and tst_elem='MPE'   then TOTAL_COMPOS_SCORE else null end) MPE_TOTAL,
        max(case when tst_cde='MPE' and tst_elem='MPER'  then TOTAL_COMPOS_SCORE else null end) MPE_COURSE,
        max(case when tst_cde='MPE'                      then DTE_TAKEN          else null end) MPE_UPLOAD_DATE,
        max(case when tst_cde='SPA' then 'SPA' else null end) SPA_TEST,
        max(case when tst_cde='SPA' and tst_elem='SPA'   then TOTAL_COMPOS_SCORE else null end) SPA_SCORE,
        max(case when tst_cde='SPA' and tst_elem='SPAR'  then TOTAL_COMPOS_SCORE else null end) SPA_COURSE,
        max(case when tst_cde='SPA'                      then DTE_TAKEN          else null end) SPA_UPLOAD_DATE,
        max(case when tst_cde='ITA' then 'ITA' else null end) ITA_TEST,
        max(case when tst_cde='ITA' and tst_elem='ITA'   then TOTAL_COMPOS_SCORE else null end) ITA_SCORE,
        max(case when tst_cde='ITA' and tst_elem='ITAR'  then TOTAL_COMPOS_SCORE else null end) ITA_COURSE,
        max(case when tst_cde='ITA'                      then DTE_TAKEN          else null end) ITA_UPLOAD_DATE,
        max(case when tst_cde='FRE' then 'FRE' else null end) FRA_TEST,
        max(case when tst_cde='FRE' and tst_elem='FRE'   then TOTAL_COMPOS_SCORE else null end) FRA_SCORE,
        max(case when tst_cde='FRE' and tst_elem='FRER'  then TOTAL_COMPOS_SCORE else null end) FRA_COURSE,
        max(case when tst_cde='FRE'                      then DTE_TAKEN          else null end) FRA_UPLOAD_DATE
    FROM
        cte_exam_detail
    GROUP BY
        ID_NUM
)
-- select * from cte_exams where FRE_TEST > '!';

SELECT
    s.SUG           slate_guid,
    p.ID_NUM        cx_id,
    case when f.ID_NUM > 0 then 'Y' else 'N' end
                    fye_attended,
    x.mpe_test,
    x.mpe_score,
    x.mpe_total,
    x.mpe_course,
    x.mpe_upload_date,
    x.spa_test,
    x.spa_score,
    x.spa_course,
    x.spa_upload_date,
    x.ita_test,
    x.ita_score,
    x.ita_course,
    x.ita_upload_date,
    x.fra_test,
    x.fra_score,
    x.fra_course,
    x.fra_upload_date
FROM
    cte_pop p
    JOIN
    cte_exams x on (p.ID_NUM = x.ID_NUM)
    LEFT JOIN
    cte_fye f on (x.ID_NUM = f.ID_NUM)
    LEFT JOIN
    cte_slateids s on (x.ID_NUM = s.ID_NUM)
;

    set nocount off;
    REVERT
END

;
GO

