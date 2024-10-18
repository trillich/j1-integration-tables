SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[MCM_GetASC_stuDemDaily]
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
    declare @nxtyr as INT        = @curyr + 1;
    declare @prvyr as INT        = @curyr - 1;

    declare @nterm as VARCHAR(6) = '2024SP'; -- for debugging
    SET @nterm = dbo.MCM_FN_CALC_TRM('N');
    SET @nterm = right(@nterm,2);

-- new students:
-- *EML with @merrimack.edu
-- stage=DEPT NMDEP

WITH
cteStuCur as (
--get current registered students
select DISTINCT sch.ID_NUM, dh.DIV_CDE
from STUDENT_CRS_HIST sch
	inner join DEGREE_HISTORY dh on sch.ID_NUM = dh.ID_NUM and sch.STUD_DIV = dh.DIV_CDE
where (sch.YR_CDE = @curyr)
	and sch.TRANSACTION_STS IN ('C', 'H', 'D')
),
cteStuPrev as (
--get previous term registered students who don't exist in the current student pop
select DISTINCT sch.ID_NUM, max(dh.DIV_CDE) DIV_CDE --max puts UG first since they can be registered for UG and GR classes at the same time.
from STUDENT_CRS_HIST sch
	inner join DEGREE_HISTORY dh on sch.ID_NUM = dh.ID_NUM and sch.STUD_DIV = dh.DIV_CDE
	left join cteStuCur on sch.ID_NUM = cteStuCur.ID_NUM
where (sch.YR_CDE = @prvyr)
	and sch.TRANSACTION_STS IN ('C', 'H', 'D')
	and cteStuCur.ID_NUM is null
group by sch.ID_NUM
),
cteAdm as (
--get deposited students for the upcoming term that do not exist in the current term 
--just in case they switched from UG to GR between current term and next term
	select cand.ID_NUM, cand.DIV_CDE
	from candidacy cand
		inner join AlternateContactMethod acm on cand.ID_NUM = acm.ID_NUM and acm.ADDR_CDE = '*EML'
		left join cteStuCur on cteStuCur.ID_NUM = cand.ID_NUM
	where (cand.YR_CDE = @curyr and cand.TRM_CDE = @nterm
		and cand.CUR_CANDIDACY = 'Y'
		and cand.stage in ('DEPT', 'NMDEP'))
		and acm.AlternateContact like '%@merrimack.edu'
		and cteStuCur.ID_NUM is null
),
cte_Pop as (
	select *
	from cteStuCur
	union all 
	select * 
	from cteStuPrev
	union all
	select *
	from cteAdm
)
-- select * from ctepop order by ID_NUM;
,

-- ==--==--==--==--==--==--== --
cte_slateids as (
    SELECT
        ID_NUM,
        max(case when IDENTIFIER_TYPE='SUG' then IDENTIFIER else null end) SUG,
        max(case when IDENTIFIER_TYPE='SGPS' then IDENTIFIER else null end) SGPS
    FROM
        ALTERNATE_IDENTIFIER ai WITH (nolock)
    WHERE
        ai.ID_NUM in ( select ID_NUM from cte_pop )
        and ai.IDENTIFIER_TYPE in ('SUG','SGPS')
        and (ai.BEGIN_DTE is null or ai.BEGIN_DTE <= getdate())
        and (ai.END_DTE is null or ai.END_DTE > getdate())
    GROUP BY ID_NUM
)
,
cte_email AS (
    SELECT
        acm.id_num,
        acm.alternatecontact        email,
        LEFT(acm.alternatecontact, Charindex('@', acm.alternatecontact) - 1)
                                    username
         FROM   alternatecontactmethod acm WITH (nolock)
         WHERE  acm.addr_cde = '*EML'
            AND acm.alternatecontact LIKE '%@merrimack.edu'
            AND acm.ID_NUM in ( select id_num from cte_pop )
)
-- select * from cte_email;
,
cte_bio as (
    SELECT
        slt.SUG             slate_id,
        slt.SGPS            slate_guid_asc,
        nm.ID_NUM           cx_id,
        nm.FIRST_NAME       first_name,
        coalesce(nm.PREFERRED_NAME,nm.FIRST_NAME)
                            pref_first_name,
        nm.LAST_NAME        last_name,
        nm.MIDDLE_NAME      middle_name,
        nm.SUFFIX           suffix_name,
        email.username      network_username,
        bm.BIRTH_DTE        birthday,
        bm.GENDER           gender,
        ethnic.IPEDS_Desc   ethnicity,
        CASE
            WHEN ethnic.ethnic_rpt_def_num = -1
            THEN 'Y'
            ELSE 'N'
        END                 hispanic,
        bm.CITIZEN_OF       citizen, -- FIXME
            -- in CX this is 'U.S.Citizen'/'Dual Citizenship'/'DACA Approved'/'Refugee'... etc
        'FIXME'             visa,
            -- F-1, IP, B-2, OTH, PR, F-1, H-4 ...etc
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
        aml.COUNTRY         mail_ctry
    FROM
        NameMaster nm with (nolock)
        join
        BIOGRAPH_MASTER bm with (nolock)
            on nm.ID_NUM = bm.ID_NUM
        left join
        cte_email email
            on nm.ID_NUM = email.ID_NUM
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

        LEFT JOIN cte_slateids slt
            on nm.ID_NUM = slt.ID_NUM

    WHERE
        nm.ID_NUM in ( select id_num from cte_pop )
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
        STRING_AGG(concat(nm.FIRST_NAME,' ',nm.LAST_NAME),',') roommates
    FROM
        STUD_ROOMMATES sr
        join
        NameMaster nm
        on sr.ROOMMATE_ID = nm.ID_NUM
    WHERE
        sr.ID_NUM in ( select id_num from cte_pop )
        and
        sr.SESS_CDE like concat('%',cast(@curyr as char(4))) -- FA or SP of the current (acad) year
        -- FIXME this probably isn't workable for when SP is waaaaay off and not populated
    GROUP BY
        sr.ID_NUM,sr.SESS_CDE,sr.BLDG_CDE,sr.ROOM_CDE
)
-- select id_num,STRING_AGG(roommate_name,',') from cte_roomies_detail group by ID_NUM;
,
cte_roomies as (
    SELECT
        id_num,
        max(case when term='FA' then SESS_CDE else null end) fa_housing_semyr,
        max(case when term='SP' then SESS_CDE else null end) sp_housing_semyr,
        max(case when term='FA' then 'R' else 'C' end) fa_housing_intend, -- FIXME
        max(case when term='SP' then 'R' else 'C' end) sp_housing_intend, -- FIXME
        max(case when term='FA' then concat(BLDG_CDE,' ',ROOM_CDE) else null end) fa_housing_bldg_room,
        max(case when term='SP' then concat(BLDG_CDE,' ',ROOM_CDE) else null end) sp_housing_bldg_room,
        max(case when term='FA' then 'FIXME' else null end) fa_housing_withdraw_date,
        max(case when term='SP' then 'FIXME' else null end) sp_housing_withdraw_date,
        max(case when term='FA' then roommates else null end) fa_housing_suitemates,
        max(case when term='SP' then roommates else null end) sp_housing_suitemates
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
        HOLD_CDE
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
        max(case when HOLD_CDE in ('PC','RE'     ) then HOLD_CDE else null end) registrarion_hold
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
        SUBMIT_DATE as IAMHERE_DATE -- FIXME? not sure which date field to use
    FROM
        MCM_BACK_TO_MACK
    WHERE
        ID_NUM in ( select ID_NUM from cte_pop ) AND
        TRM_CDE = right(@cterm,2) AND
        YR = @curyr
)
-- select * from cte_back2mack;

select
    bio.*,
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
    'FIXME'             austin_scholar,
    hold.health_hold,
    hold.bursar_hold,
    hold.registrarion_hold,
    b2m.iamhere,
    b2m.IAMHERE_DATE
from
    cte_bio bio
    JOIN
    cte_roomies rm
    on bio.cx_id = rm.ID_NUM
    LEFT JOIN
    cte_hold hold
    on bio.cx_id = hold.ID_NUM
    LEFT JOIN
    cte_back2mack b2m
    on bio.cx_id = b2m.ID_NUM
ORDER BY
    bio.cx_id
-- where mail_addrline1 > '!'
;

    set nocount off;
    REVERT
END

;
GO
