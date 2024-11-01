SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[MCM_GetASC_courseCurDaily]
    @lastpull as datetime
WITH EXECUTE AS 'dbo'
AS
-- =============================================
-- Author:		Will Trillich (Serensoft)	
-- Create date: 10/11/2024
-- Description:	Generate ASC course export for slate
-- Modified:	
-- =============================================
BEGIN
     set nocount on;

    declare @cterm as VARCHAR(6) = '2024FA'; -- for debugging
    SET @cterm = dbo.MCM_FN_CALC_TRM('C');
    declare @curyr as INT        = cast(left(@cterm,4) as int);
	declare @curtrm as char(2) = right(@cterm, 2);
    declare @prvyr as INT        = @curyr - 1;

-- [JZMCM-SQL].[J1TEST].[dbo]. <== table prefix for LIVE-ish database
-- select count(*) from namemaster;
-- select count(*) from [JZMCM-SQL].[J1TEST].[dbo].namemaster;

WITH
cteStuCur as (
	--get current registered students
	select sch.ID_NUM, dh.DIV_CDE, MAX(sch.JOB_TIME) sch_job_time, MAX(dh.JOB_TIME) dh_job_time
	from STUDENT_CRS_HIST sch
		inner join DEGREE_HISTORY dh WITH (NOLOCK) on sch.ID_NUM = dh.ID_NUM and sch.STUD_DIV = dh.DIV_CDE and dh.CUR_DEGREE = 'Y'
	where (sch.YR_CDE = @curyr)
		and sch.TRANSACTION_STS IN ('C', 'H', 'D')
	group by sch.ID_NUM, dh.DIV_CDE
),
cteStuPrev as (
	--get previous term registered students who don't exist in the current student pop
	select DISTINCT sch.ID_NUM, max(dh.DIV_CDE) DIV_CDE, --max puts UG first since they can be registered for UG and GR classes at the same time.
		MAX(sch.JOB_TIME) sch_job_time, MAX(dh.JOB_TIME) dh_job_time
	from STUDENT_CRS_HIST sch
		inner join DEGREE_HISTORY dh on sch.ID_NUM = dh.ID_NUM and sch.STUD_DIV = dh.DIV_CDE
	where (sch.YR_CDE = @prvyr)
		and sch.TRANSACTION_STS IN ('C', 'H', 'D')
	group by sch.ID_NUM
),
cte_Pop as (
	select  ID_NUM, DIV_CDE, CASE WHEN sch_job_time >= dh_job_time THEN sch_job_time ELSE dh_job_time END JOB_TIME--, cte
	from cteStuCur

	union all 

	select ID_NUM, DIV_CDE, CASE WHEN sch_job_time >= dh_job_time THEN sch_job_time ELSE dh_job_time END JOB_TIME--, cte
	from cteStuPrev 
	where NOT EXISTS (select * from cteStuCur where cteStuCur.ID_NUM = cteStuPrev.ID_NUM)
	
), 

cte_slateids as (
    SELECT
        ID_NUM,
        IDENTIFIER SCON,
		JOB_TIME
    FROM
        ALTERNATE_IDENTIFIER ai WITH (nolock)
    WHERE
        ai.ID_NUM in ( select ID_NUM from cte_pop )
        and ai.IDENTIFIER_TYPE = 'SCON'
        and (ai.BEGIN_DTE is null or ai.BEGIN_DTE <= getdate())
        and (ai.END_DTE is null or ai.END_DTE > getdate())
)
-- select * from cte_slateids where sgps > '!';
,
cte_crs as (
    SELECT
		crs.APPID, --This will be used in Slate to find an existing record and only update
        crs.ID_NUM,
        crs.STUD_DIV,
        crs.trm_cde + crs.yr_cde    cw_sessyr,
		crs.YR_CDE, 
		crs.TRM_CDE, 
        crs.SUBTERM_CDE,
        crs.CRS_CDE,
        crs.crs_title,
        crs.TUITION_HRS,
        crs.GRADE_CDE,
        crs.MIDTERM_GRA_CDE,
        case 
            when crs.DROP_DTE is not null
            then 'D' --dropped
            when crs.WITHDRAWAL_DTE is not null
            then 'W' --withdrawn
			when secm.CRS_CANCEL_FLG = 'Y' 
			then 'X' --canceled
            else 'R' --registered
        END                         cw_stat,
        crs.REPEAT_FLAG,
        replace(crs.CRS_CDE,' ','')
            + '_'
            + replace(
                + crs.TRM_CDE
                + crs.YR_CDE
                + coalesce(crs.SUBTERM_CDE,'')
                ,' ','')            cw_unique_courseid,
        idd.INSTITUT_DIV_DESC       cw_crs_area, 
		crs.JOB_TIME
    FROM
        STUDENT_CRS_HIST crs
        INNER HASH JOIN
        cte_pop pop
            ON crs.ID_NUM = pop.ID_NUM and crs.STUD_DIV = pop.DIV_CDE
		INNER JOIN SECTION_MASTER secm WITH (NOLOCK) ON crs.CRS_CDE = secm.CRS_CDE and crs.YR_CDE = secm.YR_CDE 
			and crs.TRM_CDE = secm.TRM_CDE and crs.CRS_DIV = secm.DIVISION_CDE
		LEFT JOIN INSTIT_DIVISN_DEF idd WITH (NOLOCK) ON secm.INSTITUT_DIV_CDE = idd.INSTITUT_DIV_CDE
	WHERE crs.YR_CDE = @curyr and crs.TRM_CDE = @curtrm --current course history only
)
,
-- select * from cte_crs;
cte_fac_detail as (
    SELECT DISTINCT
        fl.CRS_CDE
        ,fl.INSTRCTR_ID_NUM
        ,nm.FIRST_NAME
        ,nm.LAST_NAME
        ,nm.FIRST_NAME + ' ' + nm.LAST_NAME fullname
        ,nm.LAST_NAME + ', ' + nm.FIRST_NAME alfaname
        ,acm.AlternateContact fac_email
        ,fl.TRM_CDE
        ,fl.YR_CDE
		,fl.JOB_TIME
        ,DENSE_RANK() over (partition by fl.YR_CDE, fl.TRM_CDE, fl.CRS_CDE order by fl.LEAD_INSTRCTR_FLG desc, fl.LOAD_PERCENTAGE, fl.INSTRCTR_ID_NUM) ix
    FROM
        FACULTY_LOAD_TABLE fl with (nolock)
        JOIN
        NameMaster nm with (nolock)
        on nm.ID_NUM = fl.INSTRCTR_ID_NUM
        LEFT JOIN
        AlternateContactMethod acm with (nolock)
        on fl.INSTRCTR_ID_NUM = acm.ID_NUM and acm.ADDR_CDE = '*EML'
    WHERE
        nm.LAST_NAME not like 'TBA %'
        and exists (select * from cte_crs where cte_crs.crs_cde = fl.crs_cde and cte_crs.YR_CDE = fl.YR_CDE and cte_crs.TRM_CDE = fl.TRM_CDE)
)
-- select * from cte_fac;
,
cte_fac as (
    SELECT
        CRS_CDE,
        YR_CDE,
        TRM_CDE,

        max(case when ix=1 then INSTRCTR_ID_NUM else null end) fac1_id,
        max(case when ix=1 then fac_email else null end) fac1_email,
        max(case when ix=1 then FIRST_NAME else null end) fac1_fname,
        max(case when ix=1 then LAST_NAME else null end) fac1_lname,

        max(case when ix=2 then INSTRCTR_ID_NUM else null end) fac2_id,
        max(case when ix=2 then fac_email else null end) fac2_email,
        max(case when ix=2 then FIRST_NAME else null end) fac2_fname,
        max(case when ix=2 then LAST_NAME else null end) fac2_lname,

        max(case when ix=3 then INSTRCTR_ID_NUM else null end) fac3_id,
        max(case when ix=3 then fac_email else null end) fac3_email,
        max(case when ix=3 then FIRST_NAME else null end) fac3_fname,
        max(case when ix=3 then LAST_NAME else null end) fac3_lname, 
		max(job_time) JOB_TIME
    FROM
        cte_fac_detail
    GROUP BY
        CRS_CDE,YR_CDE,TRM_CDE
)
-- select * from cte_fac;
,
cteAll as (
	SELECT
	crs.APPID, 
    slate.SCON			slate_guid,
    pop.ID_NUM          mc_id,
    pop.DIV_CDE         cw_prog,
    crs.cw_sessyr,
    crs.SUBTERM_CDE     cw_subsess,
    crs.CRS_CDE         cw_crs_no,
    crs.CRS_TITLE       cw_crs_title,
    crs.cw_unique_courseid,
    crs.TUITION_HRS     cw_hrs,
    crs.GRADE_CDE       cw_final_grade,
    crs.MIDTERM_GRA_CDE cw_midterm_grade,
    crs.cw_stat,
    crs.REPEAT_FLAG     cw_crs_repeat,
    crs.cw_crs_area,
    fac.fac1_lname      cw_instr1_last,
    fac.fac1_fname      cw_instr1_first,
    fac.fac1_email      cw_instr1_email,
    fac.fac2_lname      cw_instr2_last,
    fac.fac2_fname      cw_instr2_first,
    fac.fac2_email      cw_instr2_email,
    fac.fac3_lname      cw_instr3_last,
    fac.fac3_fname      cw_instr3_first,
    fac.fac3_email      cw_instr3_email, 
	(SELECT MAX (v) FROM (VALUES (pop.JOB_TIME), (slate.JOB_TIME), (fac.JOB_TIME), (crs.JOB_TIME)) AS value(v)) as JOB_TIME
FROM
    cte_pop pop
    LEFT JOIN
    cte_slateids slate
    on (pop.ID_NUM=slate.ID_NUM)
    JOIN
    cte_crs crs
    on (pop.ID_NUM=crs.ID_NUM and pop.DIV_CDE=crs.STUD_DIV)
    LEFT JOIN
    cte_fac fac
    on (crs.CRS_CDE=fac.CRS_CDE and crs.cw_sessyr=fac.TRM_CDE+fac.YR_CDE)
)
SELECT *
FROM cteAll
WHERE cteAll.JOB_TIME >= @lastpull 
ORDER BY
    mc_id,
    cw_prog,
    cw_sessyr,
    cw_crs_no

    set nocount off;
    REVERT
END

;
GO
