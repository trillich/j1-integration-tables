SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[MCM_GetASC_stuDemDaily]
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

    declare @cterm as VARCHAR(6) = '2024FA'; -- for debugging
    SET @cterm = dbo.MCM_FN_CALC_TRM('C');
    declare @curyr as INT        = cast(left(@cterm,4) as int);
    declare @nxtyr as INT        = @curyr + 1;
    declare @prvyr as INT        = @curyr - 1;

-- new students:
-- *EML with @merrimack.edu
-- stage=DEPT NMDEP

WITH
cteStuCur as (
--get current registered students
select sch.ID_NUM, dh.DIV_CDE, MAX(sch.JOB_TIME) sch_job_time, MAX(dh.JOB_TIME) dh_job_time--, 1 as cte
from STUDENT_CRS_HIST sch
	inner join DEGREE_HISTORY dh WITH (NOLOCK) on sch.ID_NUM = dh.ID_NUM and sch.STUD_DIV = dh.DIV_CDE and dh.CUR_DEGREE = 'Y'
where (sch.YR_CDE = @curyr)
	and sch.TRANSACTION_STS IN ('C', 'H', 'D')
group by sch.ID_NUM, dh.DIV_CDE
),
cteStuPrev as (
--get previous term registered students who don't exist in the current student pop
select DISTINCT sch.ID_NUM, max(dh.DIV_CDE) DIV_CDE, --max puts UG first since they can be registered for UG and GR classes at the same time.
	MAX(sch.JOB_TIME) sch_job_time, MAX(dh.JOB_TIME) dh_job_time--, 2 as cte
from STUDENT_CRS_HIST sch
	inner join DEGREE_HISTORY dh on sch.ID_NUM = dh.ID_NUM and sch.STUD_DIV = dh.DIV_CDE
where (sch.YR_CDE = @prvyr)
	and sch.TRANSACTION_STS IN ('C', 'H', 'D')
group by sch.ID_NUM
),
cteAdm as (
--get deposited students for the upcoming term that do not exist in the current or p term 
--just in case they switched from UG to GR between current term and next term.
--Using same criteria as GetASC_stuAdmDaily since we shouldn't be sending next term students here
--if stuAdmDaily is not sending them. Otherwise, we will have them in stuDemDaily without the ADM data.
	SELECT cand.ID_NUM, cand.DIV_CDE, cand.JOB_TIME--, 3 as cte
	FROM candidacy cand with (nolock)
        LEFT JOIN stage_history_tran h with (nolock) on (cand.ID_NUM = h.ID_NUM 
			AND cand.YR_CDE = h.YR_CDE
            AND cand.TRM_CDE = h.TRM_CDE
            AND cand.PROG_CDE = h.PROG_CDE
            AND cand.DIV_CDE = h.DIV_CDE
            AND h.hist_stage='ACPT' )
		INNER JOIN AlternateContactMethod acm on cand.ID_NUM = acm.ID_NUM and acm.ADDR_CDE = '*EML'
    WHERE ((
			--active UG terms
			(cand.div_cde = 'UG' AND cand.TRM_CDE + cand.YR_CDE IN 
				(SELECT term + [YEAR] 
				 FROM MCM_div_process WITH (NOLOCK) 
				 WHERE division = 'UG' AND process = 'MCConnectADM' AND CAST(getdate() as date) BETWEEN active_date AND inactive_date )
				)
			OR 
			--active GR terms
		   (cand.div_cde = 'GR' AND cand.TRM_CDE + cand.YR_CDE IN 
			   (SELECT term + [YEAR] 
				FROM MCM_div_process WITH (NOLOCK) 
				WHERE division = 'GR' AND process = 'MCConnectADM' AND CAST(getdate() as date) BETWEEN active_date AND inactive_date )
			   )
		  )
        AND cand.STAGE IN ( 'DEPT', 'NMDEP' )
        AND cand.CUR_CANDIDACY = 'Y'
		AND acm.AlternateContact like '%@merrimack.edu')
),
cte_Pop as (
	select  ID_NUM, DIV_CDE, CASE WHEN sch_job_time >= dh_job_time THEN sch_job_time ELSE dh_job_time END JOB_TIME--, cte
	from cteStuCur

	union all

	select ID_NUM, DIV_CDE, JOB_TIME--, cte
	from cteAdm
	where NOT EXISTS (select * from cteStuCur where cteStuCur.ID_NUM = cteAdm.ID_NUM)

	union all 

	select ID_NUM, DIV_CDE, CASE WHEN sch_job_time >= dh_job_time THEN sch_job_time ELSE dh_job_time END JOB_TIME--, cte
	from cteStuPrev 
	where NOT EXISTS (select * from cteStuCur where cteStuCur.ID_NUM = cteStuPrev.ID_NUM)
		AND NOT EXISTS (select * from cteAdm where cteAdm.ID_NUM = cteStuPrev.ID_NUM)

	
)
--select * from cte_Pop where ID_NUM = 246485
-- select * from ctepop order by ID_NUM;
,

-- ==--==--==--==--==--==--== --

cte_bio as (
    SELECT
        ai.IDENTIFIER       slate_guid,
        nm.ID_NUM           mc_id,
        nm.FIRST_NAME       first_name,
        coalesce(nm.PREFERRED_NAME,nm.FIRST_NAME)
                            pref_first_name,
        nm.LAST_NAME        last_name,
        nm.MIDDLE_NAME      middle_name,
        nm.SUFFIX           suffix_name,
        LEFT(acm.alternatecontact, Charindex('@', acm.alternatecontact) - 1)      network_username,
        bm.BIRTH_DTE        birthday,
        bm.GENDER           gender,
        ethnic.IPEDS_Desc   ethnicity,
        CASE
            WHEN ethnic.ethnic_rpt_def_num = -1
            THEN 'Y'
            ELSE 'N'
        END                 hispanic,
        bm.CITIZENSHIP_STS  citizen, 
        bm.VISA_TYPE        visa,
        nm.IS_FERPA_RESTRICTED
                            ferpa,
        amp.ADDR_LINE_1     perm_addrline1,
        amp.ADDR_LINE_2     perm_addrline2,
        amp.ADDR_LINE_3     perm_addrline3,
        amp.CITY            perm_city,
        amp.[STATE]         perm_state,
        amp.ZIP5            perm_zip,
        amp.COUNTRY         perm_ctry,
        amc.ADDR_LINE_1     curr_addrline1,
        amc.ADDR_LINE_2     curr_addrline2,
        amc.ADDR_LINE_3     curr_addrline3,
        amc.CITY            curr_city,
        amc.[STATE]         curr_state,
        amc.ZIP5            curr_zip,
        amc.COUNTRY         curr_ctry,
        aml.ADDR_LINE_1     mail_addrline1,
        aml.ADDR_LINE_2     mail_addrline2,
        aml.ADDR_LINE_3     mail_addrline3,
        aml.CITY            mail_city,
        aml.[STATE]         mail_state,
        aml.ZIP5            mail_zip,
        aml.COUNTRY         mail_ctry,
		att.ATTRIB_CDE		austin_scholar,
		(SELECT MAX (v) FROM (VALUES (pop.JOB_TIME), (nm.JOB_TIME), (bm.JOB_TIME), (ethnic.JOB_TIME), (amp.ChangeTime), (amc.ChangeTime), (aml.ChangeTime), 
			(ai.JOB_TIME), (acm.ChangeTime), (att.JOB_TIME)) AS value(v)) as JOB_TIME
    FROM cte_Pop pop
		inner hash join
        NameMaster nm with (nolock) 
			on pop.ID_NUM = nm.ID_NUM
        join
        BIOGRAPH_MASTER bm with (nolock)
            on nm.ID_NUM = bm.ID_NUM
        LEFT JOIN mcm_latest_ethnicrace_detail ethnic WITH (nolock)
            ON ( nm.id_num = ethnic.id_num )

        LEFT JOIN nameaddressmaster namp WITH (nolock) -- nam:*LHP permanent addr
            ON nm.id_num = namp.id_num
                AND namp.addr_cde = '*LHP' --*LHP address
        LEFT JOIN addressmaster amp WITH (nolock)
            ON namp.addressmasterappid = amp.appid

        LEFT JOIN nameaddressmaster namc WITH (nolock) -- nam:*CUR
            ON nm.id_num = namc.id_num
                AND namc.addr_cde = '*CUR' --*CUR current address
        LEFT JOIN addressmaster amc WITH (nolock)
            ON namc.addressmasterappid = amc.appid

        LEFT JOIN nameaddressmaster naml WITH (nolock) -- nam:PLCL
            ON nm.id_num = naml.id_num
                AND naml.addr_cde = 'PLCL' --PLCL address person local
        LEFT JOIN addressmaster aml WITH (nolock)
            ON naml.addressmasterappid = aml.appid

		LEFT JOIN ATTRIBUTE_TRANS att WITH (NOLOCK) ON nm.ID_NUM = att.ID_NUM AND att.ATTRIB_CDE = 'AUST'
		LEFT JOIN ALTERNATE_IDENTIFIER ai WITH (nolock) on nm.ID_NUM = ai.ID_NUM and ai.IDENTIFIER_TYPE in ('SCON')
		LEFT JOIN alternatecontactmethod acm WITH (nolock) on nm.ID_NUM = acm.ID_NUM and acm.addr_cde = '*EML' AND acm.alternatecontact LIKE '%@merrimack.edu'

)
-- select * from cte_bio;
,
cte_roomies_detail as (
    SELECT
        sr.ID_NUM,
        sr.SESS_CDE,
        max(SUBSTRING(sr.SESS_CDE,1,2)) term, -- cheating, yes i know
        sr.BLDG_CDE,
        sr.ROOM_CDE,
        -- sr.ROOMMATE_ID,
        STRING_AGG(concat(nm.FIRST_NAME,' ',nm.LAST_NAME),',') roommates, 
		ssa.RESIDENCE_HALL_CHECKOUT_DTE,
		ssa.RESID_COMMUTER_STS,
		max(sr.JOB_TIME) sr_job_time
    FROM
        STUD_ROOMMATES sr WITH (NOLOCK)
        join
        NameMaster nm WITH (NOLOCK)
        on sr.ROOMMATE_ID = nm.ID_NUM
		join
		STUD_SESS_ASSIGN ssa WITH (NOLOCK) on sr.ID_NUM = ssa.ID_NUM and sr.SESS_CDE = ssa.SESS_CDE
    WHERE
        sr.ID_NUM in ( select id_num from cte_pop )
        and
        sr.SESS_CDE IN (SELECT term + [YEAR] FROM MCM_div_process WHERE process = 'MCConnectHOU' AND division = 'UG' AND CAST(getdate() as date) BETWEEN active_date AND inactive_date)
    GROUP BY
        sr.ID_NUM,sr.SESS_CDE,sr.BLDG_CDE,sr.ROOM_CDE, ssa.RESIDENCE_HALL_CHECKOUT_DTE, ssa.RESID_COMMUTER_STS
)
-- select id_num,STRING_AGG(roommate_name,',') from cte_roomies_detail group by ID_NUM;
,
cte_roomies as (
    SELECT
        id_num,
        max(case when term='FA' then SESS_CDE else null end) fa_housing_semyr,
        max(case when term='SP' then SESS_CDE else null end) sp_housing_semyr,
        max(case when term='FA' then RESID_COMMUTER_STS else 'C' end) fa_housing_intend, 
        max(case when term='SP' then RESID_COMMUTER_STS else 'C' end) sp_housing_intend, 
        max(case when term='FA' then concat(BLDG_CDE,' ',ROOM_CDE) else null end) fa_housing_bldg_room,
        max(case when term='SP' then concat(BLDG_CDE,' ',ROOM_CDE) else null end) sp_housing_bldg_room,
        max(case when term='FA' then RESIDENCE_HALL_CHECKOUT_DTE else null end) fa_housing_withdraw_date,
        max(case when term='SP' then RESIDENCE_HALL_CHECKOUT_DTE else null end) sp_housing_withdraw_date,
        max(case when term='FA' then roommates else null end) fa_housing_suitemates,
        max(case when term='SP' then roommates else null end) sp_housing_suitemates, 
		max(sr_job_time) as sr_job_time
    FROM
        cte_roomies_detail
    group by
        ID_NUM
)
-- select * from cte_roomies order by ID_NUM;
,
cte_hold_detail as (
    SELECT
        ID_NUM,
        HOLD_CDE, 
		JOB_TIME
    FROM
        HOLD_TRAN
    WHERE
        ID_NUM in (select id_num from cte_pop) and
        END_DTE is null AND
        HOLD_CDE in ( 'HR','CL','CO','GC','PC','RE' )
)
-- select * from cte_hold_detail;
,
cte_hold as (
    SELECT
        ID_NUM,
        max(case when HOLD_CDE in ('HR'          ) then HOLD_CDE else null end) health_hold,
        max(case when HOLD_CDE in ('CL','CO','CG') then HOLD_CDE else null end) bursar_hold,
        max(case when HOLD_CDE in ('PC','RE'     ) then HOLD_CDE else null end) registrarion_hold,
		max(JOB_TIME) as JOB_TIME
    FROM
        cte_hold_detail
    GROUP BY
        ID_NUM
)
-- select * from cte_hold;
,
cte_back2mack as (
    SELECT
        ID_NUM,
        IAMHERE,
        SUBMIT_DATE as IAMHERE_DATE 
    FROM
        MCM_BACK_TO_MACK
    WHERE
        ID_NUM in ( select ID_NUM from cte_pop ) AND
        TRM_CDE = right(@cterm,2) AND
        YR = @curyr
),
-- select * from cte_back2mack;
cteAll as (
select
    slate_guid,
    bio.mc_id,
    bio.first_name,
    bio.pref_first_name,
    bio.last_name,
    bio.middle_name,
    bio.suffix_name,
    bio.network_username,
    bio.birthday,
    bio.gender,
    bio.ethnicity,
    bio. hispanic,
    bio.citizen, 
    bio.visa,
    bio.ferpa,
    bio.perm_addrline1,
    bio.perm_addrline2,
    bio.perm_addrline3,
    bio.perm_city,
    bio.perm_state,
    bio.perm_zip,
    bio.perm_ctry,
    bio.curr_addrline1,
    bio.curr_addrline2,
    bio.curr_addrline3,
    bio.curr_city,
    bio. curr_state,
    bio.curr_zip,
    bio.curr_ctry,
    bio.mail_addrline1,
    bio.mail_addrline2,
    bio.mail_addrline3,
    bio.mail_city,
    bio.mail_state,
    bio.mail_zip,
    bio.mail_ctry,
    rm.fa_housing_semyr,
    rm.fa_housing_intend,
    rm.fa_housing_bldg_room,
    rm.fa_housing_withdraw_date,
    rm.fa_housing_suitemates,
    rm.sp_housing_semyr,
    ''                  late_idp_housing_intend, -- FIXME maybe? I think this is always blank
    rm.sp_housing_bldg_room,
    rm.sp_housing_withdraw_date,
    rm.sp_housing_suitemates,
    bio.austin_scholar,
    hold.health_hold,
    hold.bursar_hold,
    hold.registrarion_hold,
    b2m.iamhere,
    b2m.IAMHERE_DATE, 
	(SELECT MAX (v) FROM (VALUES (bio.JOB_TIME), (rm.sr_job_time), (hold.JOB_TIME), (b2m.IAMHERE_DATE)) AS value(v)) as JOB_TIME
from
    cte_bio bio
    LEFT JOIN
    cte_roomies rm
    on bio.mc_id = rm.ID_NUM
    LEFT JOIN
    cte_hold hold
    on bio.mc_id = hold.ID_NUM
    LEFT JOIN
    cte_back2mack b2m
    on bio.mc_id = b2m.ID_NUM
)
SELECT * 
FROM cteAll
WHERE JOB_TIME >= @lastpull
ORDER BY mc_id

;

    set nocount off;
    REVERT
END

;
GO
