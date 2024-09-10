SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[MCM_GetTHDstudents]

WITH EXECUTE AS 'dbo'
AS
-- =============================================
-- Author:		Will Trillich (Serensoft)	
-- Create date: 7/29/2024...9/9/2024
-- Description:	Generate THD STUDENT data export
-- Modified:	
-- 
-- =============================================
BEGIN

        declare @cterm as varchar(6)
        declare @prevyr as int
        declare @curyr as int
        declare @nxtyr as int
        set nocount on;

        select @cterm = dbo.MCM_FN_CALC_TRM('C');
        set @curyr = cast(left(@cterm,4) as int);
        set @prevyr = @curyr - 1;
        set @nxtyr = @curyr + 1;

        SET @cterm = right(@cterm,2) + left(@cterm,4); -- SSYYYY (not YYYYSS)
        -- print 'cterm='+@cterm+', yrs=['+@prevyr+','+@curyr+','+@nxtyr+']';

WITH loa
     AS (SELECT DISTINCT x.id_num,
                         x.leave_begin_dte,
                         x.absence_cde,
                         d.absence_desc
         FROM   leaveofabsence x
                LEFT JOIN absence_def d WITH (nolock)
                       ON ( x.absence_cde = d.absence_cde )
         WHERE  ( x.leave_begin_dte <= Getdate()
                  AND ( x.leave_end_dte IS NULL
                         OR x.leave_end_dte > Getdate() ) )),
 reg_stu
     AS (SELECT DISTINCT id_num
         FROM   student_crs_hist
         WHERE  stud_div IN ( 'UG', 'GR' )
                AND yr_cde IN ( @prevyr, @curyr, @nxtyr )
                AND transaction_sts IN ( 'P', 'H', 'C', 'D' )),
 alt_ctc
     AS (SELECT id_num,
                LEFT(acm.alternatecontact, Charindex('@', acm.alternatecontact)
                                           - 1)
                   username
         FROM   alternatecontactmethod acm WITH (nolock)
         WHERE  acm.addr_cde = '*EML'
                AND acm.alternatecontact LIKE '%@merrimack.edu'),
 peml_ctc
     AS (SELECT id_num,
                acm.alternatecontact email
         FROM   alternatecontactmethod acm WITH (nolock)
         WHERE  acm.addr_cde = 'PEML'),
 can
     AS (SELECT c.id_num,
                -- candidacy_type,
                -- CASE c.candidacy_type
                --   WHEN 'F' THEN 1
                --   WHEN 'G' THEN 5
                --   ELSE 6
                -- END                                         class,
                -- hist_stage_dte,
                CONVERT(VARCHAR(10), c.hist_stage_dte, 101) enrollment_date
         FROM   candidacy c
                LEFT JOIN reg_stu r
                       ON ( c.id_num = r.id_num )
         WHERE  c.div_cde IN ( 'UG', 'GR' )
                AND c.yr_cde IN ( @prevyr, @curyr, @nxtyr )
                AND c.stage IN ( 'DEPT', 'NMDEP' )
                AND c.cur_candidacy = 'Y'
                AND r.id_num IS NULL),
 sport
    AS (
        SELECT id_num,count(*) ct
        from SPORTS_TRACKING
        where yr_cde=@curyr and TRM_CDE=left(@cterm,2)
        group by id_num
    ),
 holds
    as (
        SELECT a.ID_NUM, a.HoldDesc1, b.HoldStart1, a.HoldDesc2, b.HoldStart2, a.HoldDesc3, b.HoldStart3
        FROM (
                SELECT ID_NUM, MAX([1]) as HoldDesc1, MAX([2]) as HoldDesc2, MAX([3]) as HoldDesc3
                FROM (
                        SELECT ID_NUM
                                ,HOLD_DESC 
                                ,row_number() OVER (PARTITION BY ID_NUM ORDER BY start_dte) rownum
                        FROM HOLD_TRAN WITH (NOLOCK)
                        WHERE END_DTE is null
                    ) d
                    PIVOT
                    (
                        max(HOLD_DESC)
                        FOR rownum IN ([1], [2], [3])
                    ) piv
                GROUP BY ID_NUM
            ) a
            INNER JOIN (
                    SELECT ID_NUM, MAX([1]) as HoldStart1, MAX([2]) as HoldStart2, MAX([3]) as HoldStart3
                    FROM (
                            SELECT ID_NUM
                                    , START_DTE
                                    ,row_number() OVER (PARTITION BY ID_NUM ORDER BY start_dte) rownum
                            FROM HOLD_TRAN WITH (NOLOCK)
                            WHERE END_DTE is null
                        ) d
                        PIVOT
                        (
                            max(START_DTE)
                            FOR rownum IN ([1], [2], [3])
                        ) piv
                    GROUP BY ID_NUM
                ) b on a.ID_NUM = b.ID_NUM

    ),
 curstu
     AS (SELECT 'CURRENT'                               grp,
                nm.id_num                               PATIENT_CONTROL_ID,
                bm.ssn,
                nm.id_num                               OTHER_ID,
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
                  WHEN loa.id_num IS NULL THEN 0
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
                -- CASE
                --   WHEN sm.current_class_cde = 'FR' THEN 1
                --   WHEN sm.current_class_cde = 'SO' THEN 2
                --   WHEN sm.current_class_cde = 'JR' THEN 3
                --   WHEN sm.current_class_cde = 'SR' THEN 4
                --   WHEN sm.current_class_cde IN ( 'GR', 'GN' ) THEN 5
                --   ELSE 6 -- 'NM' or 'CE' or NULL
                -- END                                     CLASS,
                   sm.current_class_cde,
                CONVERT(VARCHAR(10), COALESCE(sdm.re_entry_dte, sdm.entry_dte),
                101)
                                                        ENROLLMENT_DATE,
                CASE
                  WHEN dh.div_cde = 'UG'
                       AND sdm.trm_hrs_attempt >= 12 THEN 3
                  WHEN dh.div_cde = 'UG'
                       AND sdm.trm_hrs_attempt > 0 THEN 2
                  WHEN dh.div_cde = 'UG' THEN 1
                  WHEN dh.div_cde = 'GR'
                       AND sdm.trm_hrs_attempt >= 8 THEN 3
                  WHEN dh.div_cde = 'GR'
                       AND sdm.trm_hrs_attempt > 0 THEN 2
                  WHEN dh.div_cde = 'GR' THEN 1
                  WHEN dh.div_cde = 'CE' THEN 1
                  ELSE 0
                END                                     STUDENT_STATUS,
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
                alt_ctc.username                        NETWORK_USER_NAME,
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
                'FIXME'                                 ACADEMIC_STATUS,
                loa.absence_desc                        LEAVE_REASON,
                loa.leave_begin_dte                     LEAVE_DATE,
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
                JOIN biograph_master bm WITH (nolock)
                  ON nm.id_num = bm.id_num
                JOIN reg_stu rs with (nolock)
                  ON nm.id_num = rs.id_num
                JOIN student_master sm WITH (nolock)
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
                LEFT JOIN loa
                       ON nm.id_num = loa.id_num
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
                LEFT JOIN alt_ctc WITH (nolock)
                       ON ( nm.id_num = alt_ctc.id_num )
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
 newstu
     AS (SELECT 'NEW'                                   grp,
                nm.id_num                               PATIENT_CONTROL_ID,
                bm.ssn,
                nm.id_num                               OTHER_ID,
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
                  WHEN loa.id_num IS NULL THEN 0
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
                -- CASE
                --   WHEN sm.current_class_cde = 'FR' THEN 1
                --   WHEN sm.current_class_cde = 'SO' THEN 2
                --   WHEN sm.current_class_cde = 'JR' THEN 3
                --   WHEN sm.current_class_cde = 'SR' THEN 4
                --   WHEN sm.current_class_cde IN ( 'GR', 'GN' ) THEN 5
                --   ELSE 6 -- 'NM' or 'CE' or NULL
                -- END                                     CLASS,
                -- can.class,
                sm.current_class_cde,
                -- CONVERT(VARCHAR(10), COALESCE(sdm.re_entry_dte, sdm.entry_dte), 101)
                --                                         ENROLLMENT_DATE,
                can.enrollment_date,
                CASE
                  WHEN dh.div_cde = 'UG'
                       AND sdm.trm_hrs_attempt >= 12 THEN 3
                  WHEN dh.div_cde = 'UG'
                       AND sdm.trm_hrs_attempt > 0 THEN 2
                  WHEN dh.div_cde = 'UG' THEN 1
                  WHEN dh.div_cde = 'GR'
                       AND sdm.trm_hrs_attempt >= 8 THEN 3
                  WHEN dh.div_cde = 'GR'
                       AND sdm.trm_hrs_attempt > 0 THEN 2
                  WHEN dh.div_cde = 'GR' THEN 1
                  WHEN dh.div_cde = 'CE' THEN 1
                  ELSE 0
                END                                     STUDENT_STATUS,
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
                alt_ctc.username                        NETWORK_USER_NAME,
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
                'FIXME'                                 ACADEMIC_STATUS,
                loa.absence_desc                        LEAVE_REASON,
                loa.leave_begin_dte                     LEAVE_DATE,
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
                JOIN biograph_master bm WITH (nolock)
                  ON nm.id_num = bm.id_num
                JOIN reg_stu rs with (nolock)
                  ON nm.id_num = rs.id_num
                JOIN can with (nolock)
                  ON nm.id_num = can.id_num
                JOIN alt_ctc WITH (nolock)
                  ON ( nm.id_num = alt_ctc.id_num )
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
                LEFT JOIN loa
                       ON nm.id_num = loa.id_num
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
both as
    (
        SELECT *
        FROM   curstu
        UNION
        SELECT *
        FROM   newstu
    )
    -- select * from both;

-- end of CTE specifications
select
    OTHER_ID                student_id,
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
    peml_ctc.email          PERSONAL_EMAIL,
    ''                      PHOTO_FILE_NAME,
    ''                      PERM_PO_BOX,
    ''                      PERM_PO_BOX_COMBO,
    ''                      ADMIT_TERM,
    case when sport.id_num is null then 0 else 1 end
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
    holds.HoldDesc1         hold1_code,
    holds.HoldStart1        hold1_date,
    holds.HoldDesc2         hold2_code,
    holds.HoldStart2        hold2_date,
    holds.HoldDesc3         hold3_code,
    holds.HoldStart3        hold3_date,
    ''                      activity_date

from both
    left join
    peml_ctc
    on both.OTHER_ID = peml_ctc.ID_NUM
    left join
    sport
    on both.OTHER_ID = sport.ID_NUM
    left join
    holds
    on both.OTHER_ID = holds.ID_NUM

;

    set nocount off;
    REVERT
END

;
GO
