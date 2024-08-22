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
                AND yr_cde IN ( 2023, 2024, 2025 )
                AND transaction_sts IN ( 'P', 'H', 'C', 'D' )),
     alt_ctc
     AS (SELECT id_num,
                LEFT(acm.alternatecontact, Charindex('@', acm.alternatecontact)
                                           - 1)
                   username
         FROM   alternatecontactmethod acm WITH (nolock)
         WHERE  acm.addr_cde = '*EML'
                AND acm.alternatecontact LIKE '%@merrimack.edu')
SELECT 'CURRENT'                               grp,
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
       'FIXME'                                 WORK_PHONE,
       pm.phone                                Mobile_Phone,
       CONVERT(VARCHAR(10), bm.birth_dte, 101) Date_Of_Birth,
       CASE
         WHEN bm.marital_sts = 'M' THEN 1 -- married
         WHEN bm.marital_sts = 'S' THEN 2 -- single
         WHEN bm.marital_sts = 'D' THEN 3 -- divorced
         WHEN bm.marital_sts = 'T' THEN 4 -- separated
         WHEN bm.marital_sts = 'W'
              AND bm.gender = 'F' THEN 5 -- widow
         WHEN bm.marital_sts = 'W'
              AND bm.gender = 'M' THEN 6 -- widower
         ELSE 7
       END                                     Marital_Status,
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
       LEFT(amc.addr_line_1, 40)               PERMANENT_ADDRESS,
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
       CASE
         WHEN dh.div_cde = 'UG'
              AND sdm.trm_hrs_attempt >= 12 THEN 'Undergraduate Full Time'
         WHEN dh.div_cde = 'UG'
              AND sdm.trm_hrs_attempt > 0 THEN 'Undergraduate Part Time'
         WHEN dh.div_cde = 'UG' THEN 'Undergraduate Not Registered'
         WHEN dh.div_cde = 'GR'
              AND sdm.trm_hrs_attempt >= 8 THEN 'Graduate Full Time'
         WHEN dh.div_cde = 'GR'
              AND sdm.trm_hrs_attempt > 0 THEN 'Graduate Part Time'
         WHEN dh.div_cde = 'GR' THEN 'Graduate Not Registered'
         WHEN dh.div_cde = 'CE' THEN 'Continuing Education'
         ELSE 'Unknown'
       END                                     STANDING,
       CASE
         WHEN sm.current_class_cde = 'FR' THEN 1
         WHEN sm.current_class_cde = 'SO' THEN 2
         WHEN sm.current_class_cde = 'JR' THEN 3
         WHEN sm.current_class_cde = 'SR' THEN 4
         WHEN sm.current_class_cde IN ( 'GR', 'GN' ) THEN 5
         ELSE 6 -- 'NM' or 'CE' or NULL
       END                                     CLASS,
       sm.current_class_cde,
       CONVERT(VARCHAR(10), COALESCE(sdm.re_entry_dte, sdm.entry_dte), 101)
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
       CASE
         WHEN white + pacific + aframer + asian + amerindian > 1 THEN 7
         WHEN amerindian > 0 THEN 1
         WHEN asian > 0 THEN 2
         WHEN pacific > 0 THEN 3
         WHEN aframer > 0 THEN 4
         WHEN white > 0 THEN 5
         ELSE 8
       END                                     RACE,
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
       LEFT(amc.addr_line_2, 40)               AS PERMANENT_ADDRESS_LINE_2,
       alt_ctc.username                        NETWORK_USER_NAME,
       'FIXME'                                 MACKCARD_ID,
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
       loa.leave_begin_dte                     LEAVE_DATE
-- -- -- -- -- -- -- -- -- -- -- -- --
FROM   namemaster nm WITH (nolock)
       JOIN biograph_master bm WITH (nolock)
         ON nm.id_num = bm.id_num
       JOIN reg_stu rs
         ON nm.id_num = rs.id_num
       LEFT JOIN stud_sess_assign ssa WITH (nolock)
              ON nm.id_num = ssa.id_num
                 AND ssa.sess_cde = 'FA2024'
       LEFT JOIN room_assign ra WITH (nolock)
              ON nm.id_num = ra.id_num
                 AND ra.sess_cde = 'FA2024'
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
       LEFT JOIN mc_latest_ethnicrace_detail ethnic WITH (nolock)
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
-- where ra.id_num > 0
ORDER  BY nm.id_num DESC -- newid() -- to randomize


;

-- ===== ===== ===== =====
-- ===== ===== ===== =====
-- ===== ===== ===== =====

SELECT id_num,
       country
FROM   nameaddressmaster namc WITH (nolock)
       JOIN addressmaster am WITH (nolock)
         ON namc.addressmasterappid = am.appid
WHERE  namc.addr_cde = '*CUR' --*WRK address
       AND country IS NOT NULL
       AND country <> 'US';

SELECT TOP 1 Suser_sname(),
             App_name();

SELECT TOP 100 CASE
                 WHEN dh.div_cde = 'CE' THEN 'Continuing Education'
                 WHEN dh.div_cde = 'UG'
                      AND sdm.trm_hrs_attempt >= 12 THEN
                 'Undergraduate Full Time'
                 WHEN dh.div_cde = 'UG'
                      AND sdm.trm_hrs_attempt > 0 THEN 'Undergraduate Part Time'
                 WHEN dh.div_cde = 'UG' THEN 'Undergraduate Not Registered'
                 WHEN dh.div_cde = 'GR'
                      AND sdm.trm_hrs_attempt >= 8 THEN 'Graduate Full Time'
                 WHEN dh.div_cde = 'GR'
                      AND sdm.trm_hrs_attempt > 0 THEN 'Graduate Part Time'
                 WHEN dh.div_cde = 'GR' THEN 'Graduate Not Registered'
                 ELSE 'Hmm'
               END standing,
               sdm.*
FROM   degree_history dh
       JOIN student_div_mast sdm
         ON ( dh.id_num = sdm.id_num
              AND dh.div_cde = sdm.div_cde )
ORDER  BY dh.id_num;

SELECT
-- mmd.MAJOR_CDE,
-- mmd.INSTITUT_DIV_CDE,
-- idd.*,
-- td.TABLE_DESC schooldesc,
*
FROM   major_minor_def mmd
       INNER JOIN instit_divisn_def idd
               ON mmd.institut_div_cde = idd.institut_div_cde
       INNER JOIN table_detail td
               ON idd.school_cde = td.table_value
                  AND td.column_name = 'SCHOOL_CDE';

SELECT id_num,
       room_assign_sts,
	   sess_cde,
	--    case when room_assign_sts='A' then 
	   *
FROM   stud_sess_assign ssa
WHERE  ssa.sess_cde = 'FA2024'
;

SELECT id_num,
       ipeds_desc,
       white,
       pacific,
       aframer,
       asian,
       amerindian,
       CASE
         WHEN white + pacific + aframer + asian + amerindian > 1 THEN 7
         WHEN amerindian > 0 THEN 1
         WHEN asian > 0 THEN 2
         WHEN pacific > 0 THEN 3
         WHEN aframer > 0 THEN 4
         WHEN white > 0 THEN 5
         ELSE 8
       END RACE,
       CASE
         WHEN ethnic_rpt_def_num = -1 THEN 2
         ELSE 1
       END hispanic
FROM   mc_latest_ethnicrace_detail
-- order by id_num desc
;

SELECT emrg_first_nme,
       emrg_last_nme,
       emrg_mobl_phn,
       emrg_relationship
FROM   cm_emerg_contacts
ORDER  BY id_num;

SELECT id_num,
       alternatecontact,
       LEFT(alternatecontact, Charindex('@', alternatecontact) - 1)
       NETWORK_USER_NAME
FROM   alternatecontactmethod
WHERE  addr_cde = '*EML'
       AND alternatecontact LIKE '%@merrimack.edu';

SELECT TOP 100 *
FROM   name_master_udf -- empty 🙄
;

SELECT mmd.major_cde,
       mmd.institut_div_cde,
       -- idd.*,
       td.table_desc schooldesc
FROM   major_minor_def mmd
       INNER JOIN instit_divisn_def idd
               ON mmd.institut_div_cde = idd.institut_div_cde
       INNER JOIN table_detail td
               ON idd.school_cde = td.table_value
                  AND td.column_name = 'SCHOOL_CDE'
;

SELECT *
FROM   major_minor_def;
;;;;;

-- EXECUTE mcm_getmedicat;