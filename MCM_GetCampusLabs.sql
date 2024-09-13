SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[MCM_GetCampusLabs]
    @exec as bit = 1
WITH EXECUTE AS 'dbo'
AS
-- =============================================
-- Author:		Will Trillich (Serensoft)	
-- Create date: 9/13/2024
-- Description:	Generate CampusLabs data export
-- Modified:	
-- =============================================
BEGIN
     set nocount on;

        declare @cterm as VARCHAR(6) = dbo.MCM_FN_CALC_TRM('C');
        declare @curyr as INT        = cast(left(@cterm,4) as int);
        declare @nxtyr as INT        = @curyr + 1;
        declare @prvyr as INT        = @curyr - 1;

        print @cterm +'/'+ cast(@curyr as varchar)

        SET @cterm = right(@cterm,2) + left(@cterm,4); -- SSYYYY (not YYYYSS)
        print concat('cterm=',@cterm,', yrs=[',@prvyr,',',@curyr,',',@nxtyr,']');

/*
    select
    sm.current_class_cde, -- FR/SO/JR/SR/GR
    count(*)
    from student_master sm WITH (nolock)
    group by sm.current_class_cde
*/

-- [JZMCM-SQL].[J1TEST].[dbo]. <== table prefix for LIVE-ish database
-- select count(*) from namemaster;
-- select count(*) from [JZMCM-SQL].[J1TEST].[dbo].namemaster;

WITH
cte_reg_stu
     AS (
        SELECT DISTINCT
            sch.id_num,
            sm.current_class_cde    ClassStanding,
            dh.MAJOR_1              Major,
            dh.MINOR_1              Minor,
            dh.DEGR_CDE             DegreeSought,
            td.TABLE_DESC           PrimarySchoolOfEnrollment
        FROM
            STUDENT_CRS_HIST sch WITH (nolock)
            JOIN
            STUDENT_MASTER sm WITH (nolock)
                on sch.ID_NUM = sm.ID_NUM
            JOIN
            DEGREE_HISTORY dh WITH (nolock)
                on sch.ID_NUM = dh.ID_NUM
            LEFT JOIN
            MAJOR_MINOR_DEF maj1 WITH (nolock)
                    ON ( dh.major_1 = maj1.major_cde )
            LEFT JOIN
            INSTIT_DIVISN_DEF idd WITH (nolock)
                ON maj1.institut_div_cde = idd.institut_div_cde
            LEFT JOIN
            TABLE_DETAIL td WITH (nolock)
                ON idd.school_cde = td.table_value
                    AND td.COLUMN_NAME = 'SCHOOL_CDE'
                    -- table_desc is 'School of Business' or Arts&Sciences etc, need to omit DAY subprogram FIXME
        WHERE sch.stud_div IN ( 'UG', 'GR' )
            AND sch.YR_CDE in (@prvyr,@curyr,@nxtyr)
            AND sch.transaction_sts IN ( 'H', 'C', 'D' )
            AND sm.CURRENT_CLASS_CDE NOT IN ( 'CE','NM','AV' )
            AND dh.MAJOR_1 <> 'GEN' -- omit nonmatric
    )
-- select * from cte_reg_stu order by id_num;
    ,
cte_names
    as (
        SELECT
            nm.ID_NUM,
            nm.FIRST_NAME           InstitutionProvidedFirstName,
            nm.LAST_NAME            InstitutionProvidedLastName,
            nm.MIDDLE_NAME          InstitutionProvidedMiddleName,
            coalesce(anmn.FirstName,nm.first_name)
                                    LegalFirstName,
            coalesce(anmn.LastName,nm.last_name)
                                    LegalLastName,
            nm.SUFFIX,
            nm.APPID
        FROM
        NameMaster nm
            LEFT JOIN
        AlternateNameMasterNames anmn
            on nm.APPID = anmn.NameMasterAppID
        WHERE
            ID_NUM in ( select id_num from cte_reg_stu )
    )
-- select * from cte_names where suffix>'!';
    ,
cte_bio
    as (
        SELECT
            bm.ID_NUM,
            bmu.card_no         CardID,
            bm.GENDER           Sex,
            format(bm.birth_dte, 'M/d/yyyy') DateOfBirth,
            ethnic.IPEDS_Desc   Ethnicity,
            CASE
                WHEN ethnic.ethnic_rpt_def_num = -1
                THEN 'Hispanic'
                ELSE ethnic.IPEDS_Desc
                END             Race,
            case 
                WHEN CITIZEN_OF <> 'US'
                THEN 'True'
                WHEN CITIZEN_OF is NULL
                then 'True'
                else 'False'
                END             International
        FROM
            BIOGRAPH_MASTER bm
            LEFT JOIN
            BIOGRAPH_MASTER_UDF bmu
                on bm.ID_NUM = bmu.ID_NUM
            LEFT JOIN mcm_latest_ethnicrace_detail ethnic WITH (nolock)
                ON ( bm.id_num = ethnic.id_num )
        WHERE
            bm.id_num in (select id_num from cte_reg_stu)
    )
-- select * from cte_bio where race='Hispanic';
    ,
cte_email
     AS (SELECT id_num,
                LEFT(acm.alternatecontact, 
                    Charindex('@', acm.alternatecontact) - 1)
                                        username,
                acm.alternatecontact    email
         FROM   alternatecontactmethod acm WITH (nolock)
         WHERE  acm.addr_cde = '*EML'
                AND acm.alternatecontact LIKE '%@merrimack.edu'
                AND id_num in ( select id_num from cte_reg_stu )
    )
-- select * from cte_email;
    ,
cte_peml
     AS (SELECT id_num,
                acm.alternatecontact    peml
         FROM   alternatecontactmethod acm WITH (nolock)
         WHERE  acm.addr_cde = 'PEML'
                AND acm.alternatecontact NOT LIKE '%@merrimack.edu'
                AND id_num in ( select id_num from cte_reg_stu )
    )
-- select * from cte_peml;
    ,
cte_sport
    AS (
        SELECT id_num,count(*) ct
        from SPORTS_TRACKING
        where
            yr_cde=@curyr and
            TRM_CDE=left(@cterm,2) and
            id_num in ( select id_num from cte_reg_stu )
        group by id_num
    )
-- select * from cte_sport;
    ,
cte_phones
    as (
        SELECT
            n.ID_NUM,
            pm_mobile.PHONE         MobilePhone,
            pm_home.PHONE           HomePhone
        FROM
            cte_names n
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
    )
-- select * from cte_phones where HomePhone<>MobilePhone;
    ,

/*
    ,
cte_curstu
     AS (SELECT 'CURRENT'                               grp,
                nm.id_num                               stu_id,
                bm.ssn,
                LEFT(nm.last_name, 30)                  last_name,
                LEFT(nm.first_name, 20)                 first_name,
                LEFT(nm.middle_name, 1)                 middle_name,
                bm.gender                               SEX,
                LEFT(am.addr_line_1, 40)                ADDRESS,
                am.city,
                am.state,
                am.postalcode                           ZIP,
                pm2.phone                               HOME_PHONE,
                ''                                      WORK_PHONE,
                pm.phone                                Mobile_Phone,
                CONVERT(VARCHAR(10), bm.birth_dte, 101) Date_Of_Birth,
                bm.marital_sts                          Marital_Status,
                '7'                                     Employment,-- FIXME
                'N/A'                                   Employer_Code,-- FIXME
                eml.alternatecontact                    EMAIL_ADDRESS,
                CASE
                  WHEN sdm.trm_hrs_attempt = 0 THEN 1
                  --not eligible  --JON**********************************************
                  ELSE 2 --eligible
                END                                     Eligibility,
                CASE
                  WHEN cte_loa.id_num IS NULL THEN 0
                  ELSE 1
                END                                     Inactive,
                CASE
                  WHEN ssa.room_assign_sts = 'A'
                -- or ra.id_num > 0 -- FIXME maybe J1CONV data is just too anemic for testing...?
                THEN ra.bldg_cde + ra.room_cde
                  ELSE ''
                END                                     CAMPUS_ADDRESS,
                --JON***************Need to use Stud_sess_assign to determine if commuter
                amc.addr_line_1                         PERMANENT_ADDRESS1,
                amc.addr_line_2                         PERMANENT_ADDRESS2,
                amc.addr_line_3                         PERMANENT_ADDRESS3,
                amc.city                                PERMANENT_CITY,
                amc.state                               PERMANENT_STATE,
                amc.postalcode                          PERMANENT_ZIP_CODE,
                tdc.table_desc                          PERMANENT_COUNTRY,
                pm2.phone                               PERMANENT_PHONE,
                --JON*********************************
                CASE
                  WHEN bm.citizen_of <> 'US' THEN 1
                  ELSE 0
                END                                     FOREIGN_STUDENT,
                bm.visa_type,
                   sm.current_class_cde,
                CONVERT(VARCHAR(10), COALESCE(sdm.re_entry_dte, sdm.entry_dte),
                101)
                                                        ENROLLMENT_DATE,
                sch.table_desc                          SCHOOL,
                --JON**************************************
                CASE
                  WHEN ssa.room_assign_sts = 'A' THEN 1
                  ELSE 2
                END                                     RESIDENCY,
                ssa.room_assign_sts,
                ethnic.IPEDS_Desc                       ethnicity,
                CASE
                  WHEN ethnic_rpt_def_num = -1 THEN 2
                  ELSE 1
                END                                     HISPANIC,
                emrg_first_nme + ' ' + emrg_last_nme    EMERNAME,
                emrg_mobl_phn                           EMERPHONE1,
                emrg_relationship                       EMERRELATIONSHIP,
                Getdate()                               LASTIMPORTDATE,
                --JON************Assuming this is just a call to Getdate() for current date?
                LEFT(am.addr_line_2, 40)                AS ADDRESS_LINE_2,
                LEFT(amc.addr_line_2, 40)               AS
                PERMANENT_ADDRESS_LINE_2,
                cte_alt_ctc.username                        NETWORK_USER_NAME,
                bmu.card_no                             MACKCARD_ID,
                --JON************In a holding pattern for this one...
                dd.div_desc                             PROGRAM,
                sch.table_desc                          Subprogram,
                --JON************Looks like this is just repeating the school
                maj1.major_minor_desc                   MAJOR1,
                maj2.major_minor_desc                   MAJOR2,
                conc1.conc_desc                         CONC1,
                conc2.conc_desc                         CONC2,
                min1.major_minor_desc                   MINOR1,
                min2.major_minor_desc                   MINOR2,
                CASE 
                    WHEN (getdate() < cte_loa.LEAVE_END_DTE or cte_loa.LEAVE_END_DTE is null)
                     AND dh.EXIT_REASON IS NULL
                    THEN 'LA' 
                    WHEN dh.EXIT_REASON IS NOT NULL
                    THEN 'WD'
                    ELSE sm.CUR_ACAD_PROBATION
                END                                     ACADEMIC_STATUS,
                cte_loa.absence_desc                    LEAVE_REASON,
                cte_loa.leave_begin_dte                 LEAVE_DATE,
                bm.SelfGenderIdentificationDefinitionAppID ident_gender,
                nm.preferred_name,
                cdt.COHORT_CDE,
                dh.EXPECT_GRAD_YR,
                dh.EXIT_DTE,
                dh.EXIT_REASON,
                dh.MAJOR_1,
                sdm.TRM_HRS_ATTEMPT,
                sdm.CAREER_HRS_EARNED,
                sdm.CAREER_GPA,
                am.ADDR_LINE_1,                         -- PERM address
                am.ADDR_LINE_2,
                am.ADDR_LINE_3,
                ''                                      addr_line_4,
                am.COUNTRY,
                pm.PHONE
         -- -- -- -- -- -- -- -- -- -- -- -- --
         FROM   namemaster nm WITH (nolock)
                left JOIN biograph_master bm WITH (nolock)
                  ON nm.id_num = bm.id_num
                inner JOIN cte_reg_stu rs with (nolock)
                  ON nm.id_num = rs.id_num
                inner JOIN student_master sm WITH (nolock)
                       ON ( sm.id_num = nm.id_num )
                LEFT JOIN BIOGRAPH_MASTER_UDF bmu with (nolock)
                  ON (bm.ID_NUM = bmu.ID_NUM)
                LEFT JOIN stud_sess_assign ssa WITH (nolock)
                       ON nm.id_num = ssa.id_num
                          AND ssa.sess_cde = @cterm
                LEFT JOIN room_assign ra WITH (nolock)
                       ON nm.id_num = ra.id_num
                          AND ra.sess_cde = @cterm
                LEFT JOIN nameaddressmaster nam WITH (nolock) -- nam:*LHP
                       ON nm.id_num = nam.id_num
                          AND nam.addr_cde = '*LHP' --*LHP address
                LEFT JOIN nameaddressmaster namw WITH (nolock)
                       ON nm.id_num = namw.id_num
                          AND namw.addr_cde = '*WRK' --*WRK address
                LEFT JOIN nameaddressmaster namc WITH (nolock) -- namc:*WRK
                       ON nm.id_num = namc.id_num
                          AND namc.addr_cde = '*CUR' --*WRK address
                LEFT JOIN addressmaster am WITH (nolock)
                       ON nam.addressmasterappid = am.appid
                LEFT JOIN table_detail td WITH (nolock)
                       ON am.country = td.table_value
                          AND td.column_name = 'country'
                LEFT JOIN addressmaster amc WITH (nolock)
                       ON namc.addressmasterappid = amc.appid
                LEFT JOIN table_detail tdc WITH (nolock)
                       ON amc.country = tdc.table_value
                          AND tdc.column_name = 'country'
                LEFT JOIN alternatecontactmethod eml WITH (nolock)
                       ON nm.id_num = eml.id_num
                          AND eml.addr_cde = '*EML' --*EML email
                LEFT JOIN namephonemaster npm WITH (nolock)
                       ON nm.appid = npm.namemasterappid
                          AND npm.phonetypedefappid = -16 --mobile phone
                LEFT JOIN phonemaster pm WITH (nolock)
                       ON npm.phonemasterappid = pm.appid
                LEFT JOIN namephonemaster npm2 WITH (nolock)
                       ON nm.appid = npm2.namemasterappid
                          AND npm2.phonetypedefappid = -2 --home phone
                LEFT JOIN phonemaster pm2 WITH (nolock)
                       ON npm2.phonemasterappid = pm2.appid
                LEFT JOIN cte_loa
                       ON nm.id_num = cte_loa.id_num
                LEFT JOIN degree_history dh WITH (nolock)
                       ON ( nm.id_num = dh.id_num
                            AND dh.cur_degree = 'Y' )
                --***JON - need this since degree_history can be multiple records per student.
                LEFT JOIN student_div_mast sdm WITH (nolock)
                       ON ( dh.id_num = sdm.id_num
                            AND dh.div_cde = sdm.div_cde
                            AND sdm.is_student_div_active = 'Y' )
                --***JON - need this to ensure current degree_history is aligned with the current student_div_mast record
                LEFT JOIN mcm_latest_ethnicrace_detail ethnic WITH (nolock)
                       ON ( nm.id_num = ethnic.id_num )
                LEFT JOIN cm_emerg_contacts emerg WITH (nolock)
                       ON ( nm.id_num = emerg.id_num
                            AND emerg.emrg_seq_num = 1 )
                LEFT JOIN cte_alt_ctc WITH (nolock)
                       ON ( nm.id_num = cte_alt_ctc.id_num )
                LEFT JOIN division_def dd WITH (nolock)
                       ON ( sdm.div_cde = dd.div_cde )
                LEFT JOIN major_minor_def maj1 WITH (nolock)
                       ON ( dh.major_1 = maj1.major_cde )
                LEFT JOIN instit_divisn_def idd WITH (nolock)
                       --Jon************************************************
                       ON maj1.institut_div_cde = idd.institut_div_cde
                --Jon************************************************
                LEFT JOIN table_detail sch WITH (nolock)
                       --Jon************************************************
                       ON idd.school_cde = sch.table_value
                          AND sch.column_name = 'SCHOOL_CDE'
                --Jon************************************************
                LEFT JOIN major_minor_def maj2 WITH (nolock)
                       ON ( dh.major_2 = maj2.major_cde )
                LEFT JOIN major_minor_def min1 WITH (nolock)
                       ON ( dh.minor_1 = min1.major_cde )
                LEFT JOIN major_minor_def min2 WITH (nolock)
                       ON ( dh.minor_2 = min2.major_cde )
                LEFT JOIN concentration_def conc1 WITH (nolock)
                       ON ( dh.concentration_1 = conc1.conc_cde )
                LEFT JOIN concentration_def conc2 WITH (nolock)
                       ON ( dh.concentration_2 = conc2.conc_cde )
                LEFT JOIN COHORT_DEFINITION cdt
                       ON ( sdm.COHORT_DEFINITION_APPID = cdt.APPID )
),
 cte_newstu
     AS (SELECT 'NEW'                                   grp,
                nm.id_num                               stu_id,
                bm.ssn,
                LEFT(nm.last_name, 30)                  last_name,
                LEFT(nm.first_name, 20)                 first_name,
                LEFT(nm.middle_name, 1)                 middle_name,
                bm.gender                               SEX,
                LEFT(am.addr_line_1, 40)                ADDRESS,
                am.city,
                am.state,
                am.postalcode                           ZIP,
                pm2.phone                               HOME_PHONE,
                ''                                      WORK_PHONE,
                pm.phone                                Mobile_Phone,
                CONVERT(VARCHAR(10), bm.birth_dte, 101) Date_Of_Birth,
                bm.marital_sts                          Marital_Status,
                '7'                                     Employment,-- FIXME
                'N/A'                                   Employer_Code,-- FIXME
                eml.alternatecontact                    EMAIL_ADDRESS,
                CASE
                  WHEN sdm.trm_hrs_attempt = 0 THEN 1
                  --not eligible  --JON**********************************************
                  ELSE 2 --eligible
                END                                     Eligibility,
                CASE
                  WHEN cte_loa.id_num IS NULL THEN 0
                  ELSE 1
                END                                     Inactive,
                CASE
                  WHEN ssa.room_assign_sts = 'A'
                -- or ra.id_num > 0 -- FIXME maybe J1CONV data is just too anemic for testing...?
                THEN ra.bldg_cde + ra.room_cde
                  ELSE ''
                END                                     CAMPUS_ADDRESS,
                --JON***************Need to use Stud_sess_assign to determine if commuter
                amc.addr_line_1                         PERMANENT_ADDRESS1,
                amc.addr_line_2                         PERMANENT_ADDRESS2,
                amc.addr_line_3                         PERMANENT_ADDRESS3,
                amc.city                                PERMANENT_CITY,
                amc.state                               PERMANENT_STATE,
                amc.postalcode                          PERMANENT_ZIP_CODE,
                tdc.table_desc                          PERMANENT_COUNTRY,
                pm2.phone                               PERMANENT_PHONE,
                --JON*********************************
                CASE
                  WHEN bm.citizen_of <> 'US' THEN 1
                  ELSE 0
                END                                     FOREIGN_STUDENT,
                bm.visa_type,
                -- cte_can.class,
                sm.current_class_cde,
                -- CONVERT(VARCHAR(10), COALESCE(sdm.re_entry_dte, sdm.entry_dte), 101)
                --                                         ENROLLMENT_DATE,
                cte_can.enrollment_date,
                sch.table_desc                          SCHOOL,
                --JON**************************************
                CASE
                  WHEN ssa.room_assign_sts = 'A' THEN 1
                  ELSE 2
                END                                     RESIDENCY,
                ssa.room_assign_sts,
                ethnic.IPEDS_Desc                       ethnicity,
                CASE
                  WHEN ethnic_rpt_def_num = -1 THEN 2
                  ELSE 1
                END                                     HISPANIC,
                emrg_first_nme + ' ' + emrg_last_nme    EMERNAME,
                emrg_mobl_phn                           EMERPHONE1,
                emrg_relationship                       EMERRELATIONSHIP,
                Getdate()                               LASTIMPORTDATE,
                --JON************Assuming this is just a call to Getdate() for current date?
                LEFT(am.addr_line_2, 40)                AS ADDRESS_LINE_2,
                LEFT(amc.addr_line_2, 40)               AS
                PERMANENT_ADDRESS_LINE_2,
                cte_alt_ctc.username                        NETWORK_USER_NAME,
                bmu.card_no                             MACKCARD_ID,
                --JON************In a holding pattern for this one...
                dd.div_desc                             PROGRAM,
                sch.table_desc                          Subprogram,
                --JON************Looks like this is just repeating the school
                maj1.major_minor_desc                   MAJOR1,
                maj2.major_minor_desc                   MAJOR2,
                conc1.conc_desc                         CONC1,
                conc2.conc_desc                         CONC2,
                min1.major_minor_desc                   MINOR1,
                min2.major_minor_desc                   MINOR2,
                CASE 
                    WHEN (getdate() < cte_loa.LEAVE_END_DTE or cte_loa.LEAVE_END_DTE is null)
                     AND dh.EXIT_REASON IS NULL
                    THEN 'LA' 
                    WHEN dh.EXIT_REASON IS NOT NULL
                    THEN 'WD'
                    ELSE sm.CUR_ACAD_PROBATION
                END                                     ACADEMIC_STATUS,
                cte_loa.absence_desc                    LEAVE_REASON,
                cte_loa.leave_begin_dte                 LEAVE_DATE,
                bm.SelfGenderIdentificationDefinitionAppID ident_gender,
                nm.preferred_name,
                cdt.COHORT_CDE,
                dh.EXPECT_GRAD_YR,
                dh.EXIT_DTE,
                dh.EXIT_REASON,
                dh.MAJOR_1,
                sdm.TRM_HRS_ATTEMPT,
                sdm.CAREER_HRS_EARNED,
                sdm.CAREER_GPA,
                am.ADDR_LINE_1,                         -- PERM address
                am.ADDR_LINE_2,
                am.ADDR_LINE_3,
                ''                                      addr_line_4,
                am.COUNTRY,
                pm.PHONE
         -- -- -- -- -- -- -- -- -- -- -- -- --
         FROM   namemaster nm WITH (nolock)
                -- JOIN cte_reg_stu rs with (nolock) -- bad dog! heel!
                --   ON nm.id_num = rs.id_num
                inner JOIN cte_can with (nolock)
                  ON nm.id_num = cte_can.id_num
                left JOIN cte_alt_ctc WITH (nolock)
                  ON ( nm.id_num = cte_alt_ctc.id_num )
                left JOIN biograph_master bm WITH (nolock)
                  ON nm.id_num = bm.id_num
                LEFT JOIN BIOGRAPH_MASTER_UDF bmu with (nolock)
                  ON (bm.ID_NUM = bmu.ID_NUM)
                LEFT JOIN stud_sess_assign ssa WITH (nolock)
                       ON nm.id_num = ssa.id_num
                          AND ssa.sess_cde = @cterm
                LEFT JOIN room_assign ra WITH (nolock)
                       ON nm.id_num = ra.id_num
                          AND ra.sess_cde = @cterm
                LEFT JOIN nameaddressmaster nam WITH (nolock)
                       ON nm.id_num = nam.id_num
                          AND nam.addr_cde = '*LHP' --*LHP address
                LEFT JOIN nameaddressmaster namw WITH (nolock)
                       ON nm.id_num = namw.id_num
                          AND namw.addr_cde = '*WRK' --*WRK address
                LEFT JOIN nameaddressmaster namc WITH (nolock)
                       ON nm.id_num = namc.id_num
                          AND namc.addr_cde = '*CUR' --*WRK address
                LEFT JOIN addressmaster am WITH (nolock)
                       ON nam.addressmasterappid = am.appid
                LEFT JOIN table_detail td WITH (nolock)
                       ON am.country = td.table_value
                          AND td.column_name = 'country'
                LEFT JOIN addressmaster amc WITH (nolock)
                       ON namc.addressmasterappid = amc.appid
                LEFT JOIN table_detail tdc WITH (nolock)
                       ON amc.country = tdc.table_value
                          AND tdc.column_name = 'country'
                LEFT JOIN alternatecontactmethod eml WITH (nolock)
                       ON nm.id_num = eml.id_num
                          AND eml.addr_cde = '*EML' --*EML email
                LEFT JOIN namephonemaster npm WITH (nolock)
                       ON nm.appid = npm.namemasterappid
                          AND npm.phonetypedefappid = -16 --mobile phone
                LEFT JOIN phonemaster pm WITH (nolock)
                       ON npm.phonemasterappid = pm.appid
                LEFT JOIN namephonemaster npm2 WITH (nolock)
                       ON nm.appid = npm2.namemasterappid
                          AND npm2.phonetypedefappid = -2 --home phone
                LEFT JOIN phonemaster pm2 WITH (nolock)
                       ON npm2.phonemasterappid = pm2.appid
                LEFT JOIN cte_loa
                       ON nm.id_num = cte_loa.id_num
                LEFT JOIN degree_history dh WITH (nolock)
                       ON ( nm.id_num = dh.id_num
                            AND dh.cur_degree = 'Y' )
                --***JON - need this since degree_history can be multiple records per student.
                LEFT JOIN student_div_mast sdm WITH (nolock)
                       ON ( dh.id_num = sdm.id_num
                            AND dh.div_cde = sdm.div_cde
                            AND sdm.is_student_div_active = 'Y' )
                --***JON - need this to ensure current degree_history is aligned with the current student_div_mast record
                LEFT JOIN student_master sm WITH (nolock)
                       ON ( sm.id_num = nm.id_num )
                -- AND sm.cur_stud_div = sdm.div_cde ) --***JON - Not necessary since student_master is a single record per student
                LEFT JOIN mcm_latest_ethnicrace_detail ethnic WITH (nolock)
                       ON ( nm.id_num = ethnic.id_num )
                LEFT JOIN cm_emerg_contacts emerg WITH (nolock)
                       ON ( nm.id_num = emerg.id_num
                            AND emerg.emrg_seq_num = 1 )
                LEFT JOIN division_def dd WITH (nolock)
                       ON ( sdm.div_cde = dd.div_cde )
                LEFT JOIN major_minor_def maj1 WITH (nolock)
                       ON ( dh.major_1 = maj1.major_cde )
                LEFT JOIN instit_divisn_def idd WITH (nolock)
                       --Jon************************************************
                       ON maj1.institut_div_cde = idd.institut_div_cde
                --Jon************************************************
                LEFT JOIN table_detail sch WITH (nolock)
                       --Jon************************************************
                       ON idd.school_cde = sch.table_value
                          AND sch.column_name = 'SCHOOL_CDE'
                --Jon************************************************
                LEFT JOIN major_minor_def maj2 WITH (nolock)
                       ON ( dh.major_2 = maj2.major_cde )
                LEFT JOIN major_minor_def min1 WITH (nolock)
                       ON ( dh.minor_1 = min1.major_cde )
                LEFT JOIN major_minor_def min2 WITH (nolock)
                       ON ( dh.minor_2 = min2.major_cde )
                LEFT JOIN concentration_def conc1 WITH (nolock)
                       ON ( dh.concentration_1 = conc1.conc_cde )
                LEFT JOIN concentration_def conc2 WITH (nolock)
                       ON ( dh.concentration_2 = conc2.conc_cde )
                LEFT JOIN COHORT_DEFINITION cdt
                       ON ( sdm.COHORT_DEFINITION_APPID = cdt.APPID )
),
cte_both as
    (
        SELECT *
        FROM   cte_curstu
        UNION
        SELECT *
        FROM   cte_newstu
    )
    -- select * from cte_both;
    -- select count(*) rex from cte_newstu;

-- end of CTE specifications
select
    stu_id                  student_id,
    first_name,
    middle_name,
    last_name,
    Date_Of_Birth,
    SEX                     gender,
    ident_gender            identified_gender,
    preferred_name,
    'Student'               person_type,
    '?'                     privacy_indicator, -- FIXME FERPA flags?
    concat(NETWORK_USER_NAME,'@merrimack.edu')
                            additional_id1, -- FIXME USERNAME
    ''                      additional_id2,
    current_class_cde       class_status,
    cohort_cde              student_status,
    EXPECT_GRAD_YR          class_year,
    MAJOR_1                 major,
    trm_hrs_attempt         credits_semester,
    career_hrs_earned       CREDITS_CUMULATIVE,
    CAREER_GPA              GPA,
    Mobile_Phone            MOBILE_PHONE,
    ''                      MOBILE_PHONE_CARRIER,
    ''                      OPT_OUT_OF_TEXT,
    concat(NETWORK_USER_NAME,'@merrimack.edu')
                            CAMPUS_EMAIL,
    cte_peml_ctc.email          PERSONAL_EMAIL,
    ''                      PHOTO_FILE_NAME,
    ''                      PERM_PO_BOX,
    ''                      PERM_PO_BOX_COMBO,
    ''                      ADMIT_TERM,
    case when cte_sport.id_num is null then 0 else 1 end
                            STUDENT_ATHLETE,
    ethnicity,
    'local'                 ADDRESS1_TYPE,
    ADDR_LINE_1             ADDRESS1_STREET_LINE_1,
    ADDR_LINE_2             ADDRESS1_STREET_LINE_2,
    ADDR_LINE_3             ADDRESS1_STREET_LINE_3,
    ADDR_LINE_4             ADDRESS1_STREET_LINE_4,
    CITY                    ADDRESS1_CITY,
    [STATE]                 ADDRESS1_STATE_NAME,
    ZIP                     ADDRESS1_ZIP,
    COUNTRY                 ADDRESS1_COUNTRY,
    PHONE                   ADDRESS1_PHONE,
    'perm'                  ADDRESS2_TYPE,
    PERMANENT_ADDRESS1      ADDRESS2_STREET_LINE_1,
    PERMANENT_ADDRESS2      ADDRESS2_STREET_LINE_2,
    PERMANENT_ADDRESS3      ADDRESS2_STREET_LINE_3,
    ''                      ADDRESS2_STREET_LINE_4,
    PERMANENT_CITY          ADDRESS2_CITY,
    PERMANENT_STATE         ADDRESS2_STATE_NAME,
    PERMANENT_ZIP_CODE      ADDRESS2_ZIP,
    PERMANENT_COUNTRY       ADDRESS2_COUNTRY,
    PERMANENT_PHONE         ADDRESS2_PHONE,
    ''                      ADDRESS3_TYPE,
    ''                      ADDRESS3_STREET_LINE_1,
    ''                      ADDRESS3_STREET_LINE_2,
    ''                      ADDRESS3_STREET_LINE_3,
    ''                      ADDRESS3_STREET_LINE_4,
    ''                      ADDRESS3_CITY,
    ''                      ADDRESS3_STATE_NAME,
    ''                      ADDRESS3_ZIP,
    ''                      ADDRESS3_COUNTRY,
    ''                      ADDRESS3_PHONE,
    ''                      CONTACT1_TYPE,
    EMERNAME                CONTACT1_NAME,
    EMERRELATIONSHIP        CONTACT1_RELATIONSHIP,
    EMERPHONE1              CONTACT1_HOME_PHONE,
    ''                      CONTACT1_WORK_PHONE,
    ''                      CONTACT1_MOBILE_PHONE,
    ''                      CONTACT1_EMAIL,
    ''                      CONTACT1_STREET,
    ''                      CONTACT1_STREET2,
    ''                      CONTACT1_CITY,
    ''                      CONTACT1_STATE,
    ''                      CONTACT1_ZIP,
    ''                      CONTACT1_COUNTRY,
    ''                      CONTACT2_TYPE,
    ''                      CONTACT2_NAME,
    ''                      CONTACT2_RELATIONSHIP,
    ''                      CONTACT2_HOME_PHONE,
    ''                      CONTACT2_WORK_PHONE,
    ''                      CONTACT2_MOBILE_PHONE,
    ''                      CONTACT2_EMAIL,
    ''                      CONTACT2_STREET,
    ''                      CONTACT2_STREET2,
    ''                      CONTACT2_CITY,
    ''                      CONTACT2_STATE,
    ''                      CONTACT2_ZIP,
    ''                      CONTACT2_COUNTRY,
    ''                      CONTACT3_TYPE,
    ''                      CONTACT3_NAME,
    ''                      CONTACT3_RELATIONSHIP,
    ''                      CONTACT3_HOME_PHONE,
    ''                      CONTACT3_WORK_PHONE,
    ''                      CONTACT3_MOBILE_PHONE,
    ''                      CONTACT3_EMAIL,
    ''                      CONTACT3_STREET,
    ''                      CONTACT3_STREET2,
    ''                      CONTACT3_CITY,
    ''                      CONTACT3_STATE,
    ''                      CONTACT3_ZIP,
    ''                      CONTACT3_COUNTRY,
    @cterm                  TERM,
    ''                      Departure_Plan_Date,
    ''                      Depart_Plan,
    ''                      session,
    ''                      year,
    ''                      relative_description,
    ''                      location,
    ''                      travel_plan,
    EXIT_DTE                Withdrawal_date,
    EXIT_REASON             Withdrawal_reason,
    concat(cohort_cde, EXPECT_GRAD_YR)
                            cohort_ctgry,
    ''                      cohort_year,
    ''                      adm_year,
    ''                      adm_sess,
    cte_holds.HoldDesc1     hold1_code,
    cte_holds.HoldStart1    hold1_date,
    cte_holds.HoldDesc2     hold2_code,
    cte_holds.HoldStart2    hold2_date,
    cte_holds.HoldDesc3     hold3_code,
    cte_holds.HoldStart3    hold3_date,
    ''                      activity_date

from cte_both
    left join
    cte_peml_ctc
    on cte_both.stu_id = cte_peml_ctc.ID_NUM
    left join
    cte_sport
    on cte_both.stu_id = cte_sport.ID_NUM
    left join
    cte_holds
    on cte_both.stu_id = cte_holds.ID_NUM
*/

    set nocount off;
    REVERT
END

;
GO
