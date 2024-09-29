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

    SET @cterm = concat(right(@cterm,2),cast(@curyr as char(4)));

with
cte_stu as (
    select
        sm.ID_NUM,
        can.CUR_STAGE           stage, -- FIXME if this ain't right
        sm.CURRENT_CLASS_CDE    class,
        can.CUR_DIV             div,
        sm.ENTRANCE_TRM,
        sm.ENTRANCE_YR
    from
        STUDENT_MASTER sm
        JOIN
        CANDIDATE can
        ON (sm.ID_NUM = can.ID_NUM and sm.CUR_STUD_DIV = can.CUR_DIV)
        /*
        on CX we also used webuserid_table to make sure they had evolved to 
        at least have a real user_name (not just digits, something > 'A')...
        also id_rec.valid <> 'N'
        */
    WHERE
        sm.ENTRANCE_YR in ( @curyr, @nxtyr )
    )
-- select * from cte_stu;
,
cte_enrstat as (
    SELECT
        can.ID_NUM,
        can.DIV_CDE     div
    FROM
        CANDIDACY can
        JOIN
        cte_stu stu
        on (can.ID_NUM = stu.ID_NUM and can.DIV_CDE = stu.div and can.TRM_CDE = stu.ENTRANCE_TRM and can.YR_CDE = stu.ENTRANCE_YR)
    WHERE -- "confirmed" at any point in the past
        can.STAGE in ('DEPT','FIXME') -- in CX it was enrstat=CONFIRM|CONDPAID
)
-- select * from cte_enrstat
,
cte_cur as (
    SELECT
        sm.id_num,
        stu.div
    FROM
        STUDENT_MASTER sm
        join
        cte_stu stu
        on (sm.ID_NUM = stu.ID_NUM and sm.CUR_STUD_DIV = stu.div)
    WHERE -- "confirmed" currently
        stu.stage in ('DEPT','FIXME') -- in CX it was enrstat=CONFIRM|CONDPAID
)
-- select * from cte_cur
,
cte_pop as (
    SELECT * from cte_enrstat
    UNION
    SELECT * from cte_cur
)
-- select * from cte_pop order by ID_NUM;
,

-- ==--==--==--==--==--==--== --

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
cte_bio as (
    SELECT
        'FIXME'             slate_id,
        'FIXME'             slate_guid_asc,
        pop.ID_NUM          cx_id,
        nm.FIRST_NAME       first_name,
        nm.FIRST_NAME       pref_first_name, -- FIXME
        nm.LAST_NAME        last_name,
        nm.MIDDLE_NAME      middle_name,
        nm.SUFFIX           suffix_name,
        email.username      network_username,
        bm.BIRTH_DTE        birthday,
        bm.GENDER           gender,
        eth.IPEDS_Desc      ethnicity, -- FIXME maybe? on CX this was e.g. "Black,Asian" comma-separated combined descrips
        CASE
            WHEN ethnic.ethnic_rpt_def_num = -1
            THEN 'Y'
            ELSE 'N'
        END                 hispanic,
        bm.CITIZEN_OF       citizen, -- FIXME
            -- in CX this is 'U.S.Citizen'/'Dual Citizenship'/'DACA Approved'/'Refugee'... etc
        'FIXME'             visa,
            -- F-1, IP, B-2, OTH, PR, F-1, H-4 ...etc
        'FIXME'             ferpa, -- profile_rec.ferpa in CX = Y|N
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
        cte_pop pop
        join
        NameMaster nm with (nolock)
            on pop.id_num = nm.id_num
        join
        BIOGRAPH_MASTER bm with (nolock)
            on pop.ID_NUM = bm.ID_NUM
        left join
        cte_email email
            on pop.ID_NUM = email.ID_NUM
        LEFT JOIN mcm_latest_ethnicrace_detail ethnic WITH (nolock)
            ON ( pop.id_num = ethnic.id_num )

        LEFT JOIN nameaddressmaster namp WITH (nolock) -- nam:*LHP permanent addr
            ON pop.id_num = namp.id_num
                AND namp.addr_cde = '*LHP' --*LHP address
        LEFT JOIN addressmaster amp WITH (nolock)
            ON namp.addressmasterappid = amp.appid

        LEFT JOIN nameaddressmaster namc WITH (nolock) -- nam:*CUR
            ON pop.id_num = namc.id_num
                AND namc.addr_cde = '*CUR' --*CUR current address
        LEFT JOIN addressmaster amc WITH (nolock)
            ON namc.addressmasterappid = amc.appid

        LEFT JOIN nameaddressmaster naml WITH (nolock) -- nam:PLCL
            ON pop.id_num = naml.id_num
                AND naml.addr_cde = 'PLCL' --PLCL address person local
        LEFT JOIN addressmaster aml WITH (nolock)
            ON naml.addressmasterappid = aml.appid

        LEFT JOIN MCM_Latest_EthnicRace_Detail eth with (nolock)
            on pop.ID_NUM = eth.id_num

)

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
    'FIXME'             austin_scholar
from
    cte_bio bio
    JOIN
    cte_roomies rm
    on bio.cx_id = rm.ID_NUM
-- where mail_addrline1 > '!'
;

    set nocount off;
    REVERT
END

;
GO
-- select year(getdate());

-- select IPEDS_Desc,count(*)
-- from mcm_latest_ethnicrace_detail
-- group by IPEDS_Desc

-- select top 100
--     nm.id_num,
--     string_agg(ADDR_CDE,',') addr_codes
-- from NameMaster nm
--     join
--     nameAddressMaster nam
--     on nm.ID_NUM = nam.ID_NUM
-- group by nm.id_num