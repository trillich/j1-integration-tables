SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[MCM_GetASC_stuProgDaily]
    @lastpull as datetime
WITH EXECUTE AS 'dbo'
AS
-- =============================================
-- Author:		Will Trillich (Serensoft)	
-- Create date: 10/8/2024
-- Description:	Generate ASC program export for slate
-- Modified:	
-- =============================================
BEGIN
     set nocount on;

        declare @cterm as VARCHAR(6) = '2024FA'; -- for debugging
        -- set @cterm = dbo.MCM_FN_CALC_TRM('C');
        declare @curyr as INT        = cast(left(@cterm,4) as int);
        SET @cterm = right(@cterm,2);
		declare @prvyr as INT        = @curyr - 1;

-- [JZMCM-SQL].[J1TEST].[dbo]. <== table prefix for LIVE-ish database
-- select count(*) from namemaster;
-- select count(*) from [JZMCM-SQL].[J1TEST].[dbo].namemaster;

	WITH
	cteStuCur as (
		--get current registered students
		select sch.ID_NUM, dh.DIV_CDE, MAX(dh.SEQ_NUM_2) dh_seq, MAX(sch.JOB_TIME) sch_job_time, MAX(dh.JOB_TIME) dh_job_time--, 1 as cte
		from STUDENT_CRS_HIST sch
			inner join DEGREE_HISTORY dh WITH (NOLOCK) on sch.ID_NUM = dh.ID_NUM and sch.STUD_DIV = dh.DIV_CDE and dh.CUR_DEGREE = 'Y'
		where (sch.YR_CDE = @curyr)
			and sch.TRANSACTION_STS IN ('C', 'H', 'D')
		group by sch.ID_NUM, dh.DIV_CDE
	),
	cteStuPrev as (
		--get previous term registered students who don't exist in the current student pop
		select DISTINCT sch.ID_NUM, max(dh.DIV_CDE) DIV_CDE,  MAX(dh.SEQ_NUM_2) dh_seq, --max puts UG first since they can be registered for UG and GR classes at the same time.
			MAX(sch.JOB_TIME) sch_job_time, MAX(dh.JOB_TIME) dh_job_time--, 2 as cte
		from STUDENT_CRS_HIST sch
			inner join DEGREE_HISTORY dh on sch.ID_NUM = dh.ID_NUM and sch.STUD_DIV = dh.DIV_CDE
		where (sch.YR_CDE = @prvyr)
			and sch.TRANSACTION_STS IN ('C', 'H', 'D')
		group by sch.ID_NUM
	),
	cte_Pop as (
		--put together the full population
		select  ID_NUM, DIV_CDE, dh_seq, CASE WHEN sch_job_time >= dh_job_time THEN sch_job_time ELSE dh_job_time END JOB_TIME--, cte
		from cteStuCur

		union all 

		select ID_NUM, DIV_CDE, dh_seq, CASE WHEN sch_job_time >= dh_job_time THEN sch_job_time ELSE dh_job_time END JOB_TIME--, cte
		from cteStuPrev 
		where NOT EXISTS (select * from cteStuCur where cteStuCur.ID_NUM = cteStuPrev.ID_NUM)	
	)
	--select * from cte_Pop order by id_num
	,
	cte_dh as (
		--Grab all of the degree history rows associated with the pop.
		select dh.APPID, dh.ID_NUM, dh.DIV_CDE, dh.SEQ_NUM_2, dh.DEGR_CDE, dh.CUR_DEGREE, dh.EXIT_DTE, dh.EXIT_REASON, dh.MAJOR_1, dh.MAJOR_2, 
			dh.MAJOR_3, dh.CONCENTRATION_1, dh.CONCENTRATION_2, dh.MINOR_1, dh.MINOR_2, dh.MINOR_3, dh.DEG_APPLICATION_DTE, 
			dh.EXPECT_GRAD_TRM, dh.EXPECT_GRAD_YR, dh.JOB_TIME
		from DEGREE_HISTORY dh
		where dh.ID_NUM in (select id_num from cte_Pop)
	)
	--select * from cte_dh order by id_num
	,
	cte_sdm as (
		--grab all of the student_div_mast records associated with the above degree History rows and calc the "closest" 
		--term associated with the Entry_Dte. Will be used to join to the Candidate record later.
		select sdm.ID_NUM, sdm.DIV_CDE, sdm.ENTRY_DTE, sdm.CAREER_HRS_ATTEMPT, sdm.CAREER_HRS_EARNED, sdm.CAREER_GPA, 
			sdm.TRANSFER_IN, sdm.class_cde,
			--pick the term that is closest to the entry_dte
			(select top 1 ytt.TRM_CDE + ' ' + ytt.YR_CDE enroll_trm
			 from YEAR_TERM_TABLE ytt
			 where trm_cde not in ('HD', 'TR') 
				and TRM_BEGIN_DTE is not null
			 order by ABS(DATEDIFF(d, sdm.ENTRY_DTE, trm_begin_dte))) enroll_trm, 
			 sdm.JOB_TIME
		from cte_dh dh 
			inner join STUDENT_DIV_MAST sdm on dh.ID_NUM = sdm.ID_NUM and dh.DIV_CDE = sdm.DIV_CDE
	)
	--select * from cte_sdm
	,
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
	cte_loa
		 AS (SELECT DISTINCT x.id_num,
							 x.leave_begin_dte  leave_date,
							 x.ABSENCE_CDE, 
							 d.absence_desc     leave_reason, 
							 d.JOB_TIME
			 FROM   leaveofabsence x WITH (nolock)
				JOIN
				cte_pop pop
				on ( x.id_num = pop.ID_NUM )
					LEFT JOIN absence_def d WITH (nolock)
						   ON ( x.absence_cde = d.absence_cde )
			 WHERE  ( x.leave_begin_dte <= Getdate()
					  AND ( x.leave_end_dte IS NULL
							 OR x.leave_end_dte > Getdate() ) )
	)
	-- select * from cte_loa;
	,
	cte_adv as (
		select sdm.ID_NUM, 
			sdm.DIV_CDE,
			sdm.ADVISOR_ID_NUM             prim_adv,
			acm1.AlternateContact       prim_adv_email,
			sdm.ADVISOR_ID_NUM_2             sec_adv,
			acm2.AlternateContact       sec_adv_email,
			sdm.ADVISOR_ID_NUM_3             career_adv,
			acm3.AlternateContact       career_adv_email
		from STUDENT_DIV_MAST sdm WITH (NOLOCK)
			inner join cte_Pop pop on sdm.ID_NUM = pop.ID_NUM and sdm.DIV_CDE = pop.DIV_CDE  --*****************************
			-- primary advisor:
			LEFT JOIN NameMaster advnm1 WITH (nolock) ON sdm.ADVISOR_ID_NUM = advnm1.ID_NUM 
			LEFT JOIN alternatecontactmethod acm1 WITH (nolock) ON advnm1.APPID = acm1.NameMasterAppID AND acm1.ADDR_CDE = '*EML'
			-- secondary advisor:
			LEFT JOIN NameMaster advnm2 WITH (nolock) ON sdm.ADVISOR_ID_NUM_2 = advnm2.ID_NUM
			LEFT JOIN alternatecontactmethod acm2 WITH (nolock) ON advnm2.APPID = acm2.NameMasterAppID AND acm2.ADDR_CDE = '*EML'
			-- career advisor:
			LEFT JOIN NameMaster advnm3 WITH (nolock) ON sdm.ADVISOR_ID_NUM_3 = advnm3.ID_NUM
			LEFT JOIN alternatecontactmethod acm3 WITH (nolock) ON advnm3.APPID = acm3.NameMasterAppID AND acm3.ADDR_CDE = '*EML'	
	)
	,
	cte_exemp as (
		--pulls grad students with Presidential or Provost fellowships
		select stt.ID_NUM, es.EXEMPTION_WAIVER_DEF_APPID, exw.EXEMPTION_WAIVER_CODE, exw.DESCR, stt.JOB_TIME as stt_job_time, 
			es.JOB_TIME as exempt_job_time
		from STUDENT_TERM_TABLE stt WITH (NOLOCK)
			inner join ATTRIBUTE_TRANS felm WITH (NOLOCK) ON stt.ID_NUM = felm.ID_NUM and felm.ATTRIB_CDE = 'FELM' --fellowship matched
			inner join EXEMPTION_STUDENT es WITH (NOLOCK) on stt.APPID = es.STUDENT_TERM_TABLE_APPID
			inner join EXEMPTION_WAIVER_DEF_MASTER exw WITH (NOLOCK) on es.EXEMPTION_WAIVER_DEF_APPID = exw.APPID and exw.appid in (6,7) --PRES, PROV fellows
		where stt.ID_NUM in (SELECT ID_NUM from cte_Pop)
			and stt.YR_CDE = @curyr and stt.TRM_CDE = @cterm
	)
	,
	cte_acad as (
		SELECT
			dh.APPID									rowid, 
			slate.SCON									slate_guid, 
			dh.ID_NUM,
			dh.DIV_CDE									prog_code,
			dd.div_desc									prog_desc,
			rtrim(isnull(sch.TABLE_DESC, ''))			subprog_desc,
			cd.CLASS_DESC								cl_desc,
			sdm.enroll_trm								admit_sessyr,
			right(sdm.enroll_trm, 4)					admit_yr,
			sdm.ENTRY_DTE								enr_date,
			case when dh.DEGR_CDE <> 'NM' then sdm.ENTRY_DTE else null end
														matric_date,
			CASE 
				WHEN loa.ID_NUM IS NOT NULL AND dh.EXIT_REASON IS NULL THEN loa.leave_reason 
				WHEN dh.EXIT_REASON IS NOT NULL THEN ext.TABLE_DESC
				WHEN sm.CUR_ACAD_PROBATION IS NOT NULL THEN asd.ACAD_STAND_DESC
				WHEN sm.CURRENT_CLASS_CDE = 'NM' THEN 'Non-Matriculant'
				ELSE 'Accepted - Full'
			END 										acst_desc,
			CASE 
				WHEN loa.ID_NUM IS NOT NULL AND dh.EXIT_REASON IS NULL THEN loa.ABSENCE_CDE 
				WHEN dh.EXIT_REASON IS NOT NULL THEN dh.EXIT_REASON 
				WHEN sm.CUR_ACAD_PROBATION IS NOT NULL THEN sm.CUR_ACAD_PROBATION 
				WHEN sm.CURRENT_CLASS_CDE = 'NM' THEN 'NM'
				ELSE 'ACPT'
			END											acst_code,
			loa.leave_reason,
			loa.leave_date,
			dh.MAJOR_1									major1_code,
			maj1.MAJOR_MINOR_DESC						major1_desc,
			dh.MAJOR_2									major2_code,
			maj2.MAJOR_MINOR_DESC						major2_desc,
			dh.MAJOR_3									major3_code,
			maj3.MAJOR_MINOR_DESC						major3_desc,
			dh.CONCENTRATION_1							conc1_code,
			cd1.conc_desc								conc1_desc,
			dh.CONCENTRATION_2							conc2_code,
			cd2.conc_desc								conc2_desc,
			dh.MINOR_1									minor1_code,
			min1.MAJOR_MINOR_DESC						minor1_desc,
			dh.MINOR_2									minor2_code,
			min2.MAJOR_MINOR_DESC						minor2_desc,
			dh.MINOR_3									minor3_code,
			min3.MAJOR_MINOR_DESC						minor3_desc,
			dh.DEG_APPLICATION_DTE						deg_app_date,
			adv.prim_adv,
			adv.prim_adv_email,
			adv.sec_adv,
			adv.sec_adv_email,
			adv.career_adv,
			adv.career_adv_email,
			dh.EXPECT_GRAD_TRM + dh.EXPECT_GRAD_YR		plan_grad_sessyr,
			ex.EXEMPTION_WAIVER_CODE					fellowship_code, --currenr_code, --This is now becoming the Fellowship_code field since all of the other values are irrelavent now
			ex.DESCR									fellowship_desc, --currenr_desc, --This is now becoming the Fellowship_Desc field since all of the other values are irrelavent now
			CASE 
				WHEN dwpg.ID_NUM IS NOT NULL THEN dwpg.ATTRIB_CDE
				WHEN dwsr.ID_NUM IS NOT NULL THEN dwsr.ATTRIB_CDE
				ELSE sm.DISTRICT_CDE
			END											entrtype_code, --this will be pulling from sm.district_cde which is copied from Candidacy.candidacy_type now
			CASE 
				WHEN dwpg.ID_NUM IS NOT NULL THEN dwpg.ATTRIB_DEF
				WHEN dwsr.ID_NUM IS NOT NULL THEN dwsr.ATTRIB_DEF
				ELSE ctd.CANDIDACY_TYP_DESC
			END											entrtype_desc, --this will be pulling from sm.district_cde which is copied from Candidacy.candidacy_type now
			sdm.TRANSFER_IN								[transfer],
			case when hon.ID_NUM > 0 then 'Y' else 'N' end	honors,
			sm.UDEF_1A_4								[online], 
			CASE 
				WHEN dh.EXIT_REASON IN ('G', 'GR') THEN dh.degr_cde
				ELSE NULL
			END											degree_earn,
			CASE 
				WHEN dh.EXIT_REASON IN ('G', 'GR') THEN dh.EXPECT_GRAD_TRM + ' ' + dh.EXPECT_GRAD_YR
				ELSE NULL
			END											degree_sessyr,
			sdm.CAREER_HRS_ATTEMPT						cum_att_hrs,
			sdm.CAREER_HRS_EARNED						cum_earn_hrs,
			sdm.CAREER_GPA								cum_gpa, 
			(SELECT MAX (v) FROM (VALUES (dh.JOB_TIME), (sdm.JOB_TIME), (slate.JOB_TIME), (loa.JOB_TIME)) AS value(v)) as JOB_TIME
		FROM
			cte_dh dh
			JOIN
			STUDENT_MASTER sm WITH (nolock)
				on (dh.ID_NUM = sm.ID_NUM )
			JOIN
			cte_sdm sdm WITH (nolock)
				ON ( dh.id_num = sdm.id_num
					AND dh.div_cde = sdm.div_cde 
				)
			JOIN
			DIVISION_DEF dd WITH (nolock)
				ON ( dh.DIV_CDE = dd.DIV_CDE )
			LEFT JOIN
			CLASS_DEFINITION cd with (nolock)
				ON ( sdm.CLASS_CDE = cd.CLASS_CDE )
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
			ATTRIBUTE_TRANS hon WITH (nolock)
				on ( dh.ID_NUM = hon.ID_NUM
					and dh.DIV_CDE = 'UG'
					and hon.ATTRIB_CDE = 'HONR'
				)
			LEFT JOIN cte_exemp ex ON dh.ID_NUM = ex.id_num
			LEFT JOIN ATTRIBUTE_TRANS dwpg WITH (NOLOCK) ON dh.ID_NUM = dwpg.ID_NUM AND dwpg.ATTRIB_CDE = 'DWPG'
			LEFT JOIN ATTRIBUTE_TRANS dwsr WITH (NOLOCK) ON dh.ID_NUM = dwsr.ID_NUM AND dwsr.ATTRIB_CDE = 'DWSR'
			LEFT JOIN CANDIDACY_TYPE_DEF ctd WITH (NOLOCK) ON sm.DISTRICT_CDE = ctd.CANDIDACY_TYPE
			LEFT JOIN INSTIT_DIVISN_DEF idd WITH (NOLOCK) ON maj1.INSTITUT_DIV_CDE = idd.INSTITUT_DIV_CDE
			LEFT JOIN TABLE_DETAIL sch WITH (NOLOCK) ON idd.SCHOOL_CDE = sch.TABLE_VALUE AND sch.COLUMN_NAME = 'school_cde'
			LEFT JOIN cte_loa loa on (dh.ID_NUM = loa.ID_NUM)
			LEFT JOIN TABLE_DETAIL ext WITH (NOLOCK) ON dh.EXIT_REASON = ext.TABLE_VALUE AND ext.COLUMN_NAME = 'exit_reason'
			LEFT JOIN ACAD_STANDING_DEF asd WITH (NOLOCK) ON (sm.CUR_ACAD_PROBATION = asd.ACAD_STAND_CODE)
			LEFT JOIN cte_adv adv on (dh.ID_NUM = adv.ID_NUM and dh.DIV_CDE = adv.DIV_CDE)
			LEFT JOIN cte_slateids slate on (dh.ID_NUM = slate.ID_NUM)
	)
	-- select * from cte_acad where conc2_code>'!';

	SELECT
		acad.rowid, 
		acad.slate_guid, 
		acad.ID_NUM						mc_id,
		acad.prog_code,
		acad.prog_desc,
		acad.subprog_desc,
		acad.cl_desc,
		acad.admit_sessyr,
		acad.admit_yr,
		acad.enr_date,
		acad.matric_date,
		acad.acst_desc,
		acad.acst_code,
		acad.major1_code,
		acad.major1_desc,
		acad.major2_code,
		acad.major2_desc,
		acad.major3_code,
		acad.major3_desc,
		acad.conc1_code,
		acad.conc1_desc,
		acad.conc2_code,
		acad.conc2_desc,
		acad.minor1_code,
		acad.minor1_desc,
		acad.minor2_code,
		acad.minor2_desc,
		acad.minor3_code,
		acad.minor3_desc,
		acad.deg_app_date,
		acad.plan_grad_sessyr,
		acad.prim_adv,
		acad.prim_adv_email,
		acad.sec_adv,
		acad.sec_adv_email,
		acad.career_adv,
		acad.career_adv_email,
		acad.leave_reason,
		acad.leave_date,
		acad.[online], 
		acad.fellowship_code,
		acad.fellowship_desc,
		acad.entrtype_code,
		acad.entrtype_desc,
		acad.honors,
		acad.[transfer],
		can.HOUSING_CDE                 adm_hsg_type,  
		acad.admit_sessyr               adm_plansessyr,
		CASE WHEN can.CUR_STAGE = 'WITH' THEN 'Withdrawn Paid' END adm_withpaid,
		acad.degree_earn,
		acad.degree_sessyr,
		acad.cum_att_hrs,
		acad.cum_earn_hrs,
		acad.cum_gpa, 
		acad.JOB_TIME
	FROM
		cte_acad acad
			LEFT JOIN CANDIDATE can WITH (NOLOCK) on acad.ID_NUM = can.ID_NUM and acad.prog_code = can.CUR_DIV 
				AND acad.admit_sessyr = can.CUR_TRM + ' ' + can.CUR_YR
	WHERE acad.JOB_TIME >= @lastpull
	ORDER BY
		acad.ID_NUM, acad.prog_code;

    set nocount off;
    REVERT
END

;
GO
