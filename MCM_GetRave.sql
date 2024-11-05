SET ANSI_NULLS ON

GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[MCM_GetRave]
    @exec as bit = 1
WITH EXECUTE AS 'dbo'
AS
-- =============================================
-- Author:		Will Trillich (Serensoft)	
-- Create date: 11/05/2024 election day
-- Description:	Generate RAVE CSV export: no header line, lots and LOTS of empty fields *rolls eyes*
-- Modified:
-- =============================================
/*
sample file:
    aagesonr,Reidar,Aageson,aagesonr@merrimack.edu,,4254177575,Student,aagesonr,,,,,,,,,,,,,,,,,,,,,,,,
    aakila,Adam,Aakil,aakila@merrimack.edu,,,Employee,aakila,,,,,,,,,9788373404,0,,,,,,,,,,,,,,
    abairn,Natalie,Abair,abairn@merrimack.edu,,8025561552,Student,abairn,,,,,,,,,,,,,,,,,,,,,,,,
if there was a header line it would look like this:
    net_addr,firstname,lastname,emlline,fld05,first_phone,inst_role,net_addr,fld09,fld10,fld11,fld12,sec_phone,fld14,third_phone,fld16,ephone,landline1_services,fld19,fld20,fld21,fld22,fld23,fld24,fld25,fld26,sess_tag,fld28,fld29,fld30,fld31,fld32
*/

BEGIN
    set nocount on;

    /*
    On CX:
        gets acad_cal_rec where beg_date >= current_date - 1year and end_date <= current_date + 1year
        (9 rows in rave_cal_rec determined by this process as of 2024-11-05) and creates records
        in (temp-ish) table rave_cal_rec.
        For WINTER/SUMMER session:
        -   uses begin/end date from acad_cal_rec for STU type
        For SPRING:
        -   uses acad_cal_rec.beg_date -7days to +10days for APP type
        -   uses acad_cal_rec.beg_date -7days to +20days for STU type
        For FALL it uses prev/next:
        -   uses acad_cal_rec.beg_date -12weeks to +10days for APP type
        -   For STU type, uses SPRING semester before and after:
            uses acad_cal_rec for PREV SP: end_date +3weeks (start date)
            acad_cal_rec for NEXT SP: beg_date -8days (end date)

        Once we have sessions and date-ranges (rave_cal_rec)...
        -   for STU type:
                pull cw_rec.id with firstname/lastname/net_addr (id_rec)
                matching on sess/yr (rave_cal_rec)
                where cw_rec.stat in (R|T|E)
        -   for APP type:
                pull adm_rec.id with firstname/lastname/net_addr (id_rec)
                matching on plane_enr_sess/plan_enr_yr
                where enrstat in (CONFIRM|CONFNODP)
        -   elsewise (for employees):
                pull involve_rec.id with firstname/lastname/net_addr (id_rec)
                where ctgry=HR and invl=MEML
                and end_date is null or in the future
        Omit anybody who doesn't have a net_addr

        For employees we pull pers_rec.room, dept, ext
        -   if ext<>0 or blank or empty, ephone = '978837' + ext

        aa_rec.aa in (CELL|MCEL|CEL2|EML) for various phones and email addr
        -   phones are purged of nondigits

    */

    declare @cterm as VARCHAR(6) = '2024FA'; -- for debugging
    SET @cterm = dbo.MCM_FN_CALC_TRM('C');
    declare @curyr as INT        = cast(left(@cterm,4) as int);
    declare @nxtyr as INT        = @curyr + 1;
    declare @prvyr as INT        = @curyr - 1;

WITH
cte_calendar as (
    SELECT
        YR_CDE,
        TRM_CDE,
        cast(TRM_BEGIN_DTE as date) begins,
        cast(TRM_END_DTE as date) ends
    FROM
        YEAR_TERM_TABLE cal with (nolock)
    WHERE
        yr_cde in ( @prvyr, @curyr ) -- kinda moot but don't hurt nuthin
        AND
        TRM_CDE in ( 'FA','SP','SU','WI' )
),
cte_cal as (
    SELECT
        -- registered student related starts/ends:
        case
            when cur.trm_cde in ( 'SU','WI' )
            then cur.begins
            when cur.trm_cde = 'SP'
            then dateadd(day,-7,cur.begins) -- 7 days before SPRING starts
            when cur.trm_cde = 'FA'
            then dateadd(week,+3,prv_sp.ends) -- 3 weeks after PREV SPRING ended
        end stu_begins,
        case
            when cur.trm_cde in ( 'SU','WI' )
            then cur.ends
            when cur.trm_cde = 'SP'
            then dateadd(day,+20,cur.ends) -- 20 days after SPRING ends
            when cur.trm_cde = 'FA'
            then dateadd(day,-7,nxt_sp.begins) -- 7 days before NEXT SPRING starts
        end stu_ends,
        -- applicant related starts/ends:
        case
            when cur.trm_cde in ( 'SU','WI' )
            then cur.ends
            when cur.trm_cde = 'SP'
            then dateadd(day,-7,cur.begins) -- 7 days before SPRING starts
            when cur.trm_cde = 'FA'
            then dateadd(week,-12,cur.begins) -- 12 weeks before FALL starts
        end app_begins,
        case
            when cur.trm_cde in ( 'SU','WI' )
            then cur.ends
            when cur.trm_cde = 'SP'
            then dateadd(day,+10,cur.ends) -- 10 days after SPRING ends
            when cur.trm_cde = 'FA'
            then dateadd(day,+10,cur.ends) -- 10 days after FALL ends
        end app_ends,
        -- prv_sp.ends prev_sp_ends,
        -- nxt_sp.begins nxt_sp_begins,
        cur.*
    FROM
        cte_calendar cur
        LEFT JOIN
        -- for FALL we need NEXT spring dates
        cte_calendar nxt_sp -- same acad year (different calendar), different semester
            on cur.TRM_CDE = 'FA'
            and nxt_sp.TRM_CDE = 'SP'
            and cur.YR_CDE = nxt_sp.YR_CDE
        LEFT JOIN
        -- for FALL we need PREVIOUS spring dates
        cte_calendar prv_sp -- different acad year (same calendar), different semester
            on cur.TRM_CDE = 'FA'
            and prv_sp.TRM_CDE = 'SP'
            and cur.YR_CDE - 1 = prv_sp.YR_CDE
)
-- select * from cte_cal -- where getdate() between stu_begins and stu_ends 
-- order by YR_CDE,begins,ends 
,
cteEmpl as (
    -- current employees FIXME is this the right source for this? zero rows in the EMPL_MAST table :(
    SELECT DISTINCT
        ID_NUM,
        'FIXME' ephone, -- office phone (cx prepended 978837 to ext and called it 'ephone')
        '' landline1_services -- sometimes 0, usually ''
    FROM
        EMPL_MAST emp with (nolock) -- FIXME is this the canonical place for employees?
    WHERE
        emp.TERMINATION_DTE is null OR
        emp.TERMINATION_DTE > getdate()
)
,
cteStuCur as (
    --get current registered students
    select DISTINCT sch.ID_NUM
    from
        STUDENT_CRS_HIST sch with (nolock)
        inner join
        cte_cal cal
            on sch.YR_CDE = cal.YR_CDE
            and sch.TRM_CDE = cal.TRM_CDE
            and cal.stu_begins <= getdate()
            and (getdate()<cal.stu_ends or cal.stu_ends is null)
        inner join
        DEGREE_HISTORY dh with (nolock)
            on sch.ID_NUM = dh.ID_NUM and sch.STUD_DIV = dh.DIV_CDE
    where sch.TRANSACTION_STS IN ('C', 'H', 'D')
        and sch.id_num not in ( select id_num from cteEmpl ) -- employee trumps student
)
,
cteAdm as (
    --get deposited students for the upcoming term that do not exist in the current term 
    --just in case they switched from UG to GR between current term and next term
	select cand.ID_NUM
	from
        candidacy cand with (nolock)
        inner join
        cte_cal cal
            on cand.YR_CDE = cal.YR_CDE
            and cand.TRM_CDE = cal.TRM_CDE
            and cal.app_begins <= getdate()
            and (cal.app_ends > getdate() or cal.app_ends is null)
        inner join
        AlternateContactMethod acm with (nolock)
            on cand.ID_NUM = acm.ID_NUM and acm.ADDR_CDE = '*EML'
		left join
            cteStuCur on cteStuCur.ID_NUM = cand.ID_NUM
	where (cand.YR_CDE = @curyr -- and cand.TRM_CDE = @nterm FIXME? I think we don't need term here, probly ish
		and cand.CUR_CANDIDACY = 'Y'
		and cand.stage in ('DEPT', 'NMDEP'))
		and acm.AlternateContact like '%@merrimack.edu'
		and cteStuCur.ID_NUM is null
        and cand.id_num not in ( select id_num from cteEmpl ) -- employee and student trump applicant
)
,
cte_Pop as (
    SELECT ID_NUM,'Employee' irole
    FROM cteEmpl
    UNION
	SELECT ID_NUM,'Student' irole
	FROM cteStuCur
	UNION
	SELECT ID_NUM,'Student' irole
	FROM cteAdm
)
-- select * from cte_pop order by ID_NUM;
,

-- ==--==--==--==--==--==--== --

cte_phones
    as (
        SELECT
            n.ID_NUM,
            max(pm_mobile.PHONE)         MobilePhone,
            max(pm_home.PHONE)           HomePhone
        FROM
            NameMaster n with (nolock)
        JOIN
            cte_pop pop
                ON n.ID_NUM = pop.ID_NUM
        LEFT JOIN
            NamePhoneMaster npm1 WITH (nolock)
                ON n.APPID = npm1.NameMasterAppID
        LEFT JOIN
            PhoneMaster pm_mobile WITH (nolock)
                ON npm1.PhoneMasterAppID = pm_mobile.AppID
                AND npm1.PhoneTypeDefAppID = -16 -- mobile phone
        LEFT JOIN
            NamePhoneMaster npm2 WITH (nolock)
                ON n.APPID = npm2.NameMasterAppID
        LEFT JOIN
            PhoneMaster pm_home WITH (nolock)
                ON npm2.PhoneMasterAppID = pm_home.AppID
                and npm2.PhoneTypeDefAppID = -2 -- home phone
        GROUP BY
            n.id_num
    )
,
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
        pop.irole
    FROM
        NameMaster nm with (nolock)
        JOIN
        cte_pop pop
            on ( nm.ID_NUM = pop.ID_NUM )
)
-- select * from cte_bio;

select
    email.username              net_addr,
    bio.FIRST_NAME              firstname,
    bio.LAST_NAME               lastname,
    email.email                 emllline,
    ''                          fld05,
    phone.MobilePhone           first_phone,
    bio.irole                   inst_role,
    email.username              net_addr_again_for_no_good_reason_i_can_find,
    ''                          fld09,
    ''                          fld10,
    ''                          fld11,
    ''                          fld12,
    phone.HomePhone             sec_phone,
    ''                          fld14,
    ''                          third_phone,
    ''                          fld16,
    emp.ephone,
    emp.landline1_services, -- for employees this is sometimes 0 but i'm guessing that's not significant
    ''                          fld19,
    ''                          fld20,
    ''                          fld21,
    ''                          fld22,
    ''                          fld23,
    ''                          fld24,
    ''                          fld25,
    ''                          fld26,
    ''                          sess_tag, -- WINTER or SUMMER maybe sometimes kinda
    ''                          fld28,
    ''                          fld29,
    ''                          fld30,
    ''                          fld31,
    ''                          fld32
from
    cte_pop pop
    JOIN
    cte_bio bio
        on pop.ID_NUM = bio.ID_NUM
    JOIN
    cte_email email
        on pop.ID_NUM = email.ID_NUM
    LEFT JOIN
    cte_phones phone
        on pop.ID_NUM = phone.ID_NUM
    LEFT JOIN
    cteEmpl emp
        on pop.ID_NUM = emp.ID_NUM
ORDER BY
    bio.LAST_NAME,
    bio.FIRST_NAME,
    pop.ID_NUM
;

    set nocount off;
    REVERT
END

;
GO
