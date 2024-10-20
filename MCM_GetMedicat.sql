SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[MCM_GetMedicat]
	@exec as bit = 1
WITH EXECUTE AS 'dbo'
AS
-- =============================================
-- Author:		Will Trillich (Serensoft)	
-- Create date: 7/29/2024...9/9/2024
-- Description:	Generate MEDICAT export data
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

WITH cte_loa
     AS (SELECT DISTINCT x.id_num,
                         x.leave_begin_dte,
                         x.absence_cde,
                         d.absence_desc
       FROM   leaveofabsence x with (nolock)
       LEFT JOIN absence_def d WITH (nolock)
              ON ( x.absence_cde = d.absence_cde )
       WHERE  ( x.leave_begin_dte <= Getdate()
              AND ( x.leave_end_dte IS NULL
                     OR x.leave_end_dte > Getdate() ) )),
 cte_reg_stu
     AS (SELECT DISTINCT id_num
         FROM   student_crs_hist with (nolock)
         WHERE  stud_div IN ( 'UG', 'GR' )
                AND yr_cde IN ( @prevyr, @curyr, @nxtyr )
                AND transaction_sts IN ( 'P', 'H', 'C', 'D' )),
 cte_alt_ctc
     AS (SELECT id_num,
                LEFT(acm.alternatecontact, 
                    Charindex('@', acm.alternatecontact) - 1)
                    username
         FROM   alternatecontactmethod acm WITH (nolock)
         WHERE  acm.addr_cde = '*EML'
                AND acm.alternatecontact LIKE '%@merrimack.edu'),
 cte_can
     AS (SELECT c.id_num,
                -- candidacy_type,
                CASE c.candidacy_type
                  WHEN 'F' THEN 1
                  WHEN 'G' THEN 5
                  ELSE 6
                END                                         class,
                -- hist_stage_dte,
                CONVERT(VARCHAR(10), c.hist_stage_dte, 101) enrollment_date
       FROM   candidacy c with (nolock)
       LEFT JOIN cte_reg_stu r with (nolock)
              ON ( c.id_num = r.id_num )
         WHERE  c.div_cde IN ( 'UG', 'GR' )
                AND c.yr_cde IN ( @prevyr, @curyr, @nxtyr )
                AND c.stage IN ( 'DEPT', 'NMDEP' )
                AND c.cur_candidacy = 'Y'
                AND r.id_num IS NULL),
 cte_curstu
     AS (SELECT 
				--'CURRENT'                               grp, --for debugging
                ''										PATIENT_CONTROL_ID,
                ''										ssn,
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
                  ELSE 2 --eligible
                END                                     Eligibility,
                CASE
                  WHEN loa.id_num IS NULL THEN 0
                  ELSE 1
                END                                     Inactive,
                CASE
                  WHEN ssa.room_assign_sts = 'A'
                THEN ra.bldg_cde + ra.room_cde
                  ELSE ''
                END                                     CAMPUS_ADDRESS,
                LEFT(amc.addr_line_1, 40)               PERMANENT_ADDRESS,
                amc.city                                PERMANENT_CITY,
                amc.state                               PERMANENT_STATE,
                amc.postalcode                          PERMANENT_ZIP_CODE,
                tdc.table_desc                          PERMANENT_COUNTRY,
                pm2.phone                               PERMANENT_PHONE,
                CASE
                  WHEN bm.citizen_of <> 'US' THEN 1
                  ELSE 0
                END                                     FOREIGN_STUDENT,
                bm.visa_type,
                CASE
                  WHEN dh.div_cde = 'UG'
                       AND sdm.trm_hrs_attempt >= 12 THEN
                  'Undergraduate Full Time'
                  WHEN dh.div_cde = 'UG'
                       AND sdm.trm_hrs_attempt > 0 THEN
                  'Undergraduate Part Time'
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
                --    sm.current_class_cde,
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
                LEFT(am.addr_line_2, 40)                AS ADDRESS_LINE_2,
                LEFT(amc.addr_line_2, 40)               AS
                PERMANENT_ADDRESS_LINE_2,
                alt_ctc.username                        NETWORK_USER_NAME,
                bmu.card_no                             MACKCARD_ID,
                dd.div_desc                             PROGRAM,
                sch.table_desc                          Subprogram,
                maj1.major_minor_desc                   MAJOR1,
                maj2.major_minor_desc                   MAJOR2,
                conc1.conc_desc                         CONC1,
                conc2.conc_desc                         CONC2,
                min1.major_minor_desc                   MINOR1,
                min2.major_minor_desc                   MINOR2,
                CASE 
					WHEN loa.ID_NUM IS NOT NULL AND dh.EXIT_REASON IS NULL THEN loa.ABSENCE_CDE + '-' + loa.ABSENCE_DESC 
					WHEN dh.EXIT_REASON IS NOT NULL THEN dh.EXIT_REASON + '-' + ext.TABLE_DESC
					WHEN sm.CUR_ACAD_PROBATION IS NOT NULL THEN sm.CUR_ACAD_PROBATION + '-' + asd.ACAD_STAND_DESC
					WHEN sm.CURRENT_CLASS_CDE = 'NM' THEN 'NM-Non_Matriculate'
					ELSE 'Unknown'
				END                                 ACADEMIC_STATUS,
                loa.absence_desc                        LEAVE_REASON,
                CONVERT(varchar(10), loa.leave_begin_dte, 101)                  LEAVE_DATE
         -- -- -- -- -- -- -- -- -- -- -- -- --
         FROM   namemaster nm WITH (nolock)
                JOIN biograph_master bm WITH (nolock)
                  ON nm.id_num = bm.id_num
                JOIN cte_reg_stu rs
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
                LEFT JOIN cte_loa loa
                       ON nm.id_num = loa.id_num
                LEFT JOIN degree_history dh WITH (nolock)
                       ON ( nm.id_num = dh.id_num
                            AND dh.cur_degree = 'Y' )
				LEFT JOIN TABLE_DETAIL ext WITH (NOLOCK) 
					   ON dh.EXIT_REASON = ext.TABLE_VALUE AND ext.COLUMN_NAME = 'exit_reason'
                LEFT JOIN student_div_mast sdm WITH (nolock)
                       ON ( dh.id_num = sdm.id_num
                            AND dh.div_cde = sdm.div_cde
                            AND sdm.is_student_div_active = 'Y' )
                LEFT JOIN mcm_latest_ethnicrace_detail ethnic WITH (nolock)
                       ON ( nm.id_num = ethnic.id_num )
                LEFT JOIN cm_emerg_contacts emerg WITH (nolock)
                       ON ( nm.id_num = emerg.id_num
                            AND emerg.emrg_seq_num = 1 )
                LEFT JOIN cte_alt_ctc alt_ctc WITH (nolock)
                       ON ( nm.id_num = alt_ctc.id_num )
                LEFT JOIN division_def dd WITH (nolock)
                       ON ( sdm.div_cde = dd.div_cde )
                LEFT JOIN major_minor_def maj1 WITH (nolock)
                       ON ( dh.major_1 = maj1.major_cde )
                LEFT JOIN instit_divisn_def idd WITH (nolock)
                       ON maj1.institut_div_cde = idd.institut_div_cde
                LEFT JOIN table_detail sch WITH (nolock)
                       ON idd.school_cde = sch.table_value
                          AND sch.column_name = 'SCHOOL_CDE'
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
                LEFT JOIN ACAD_STANDING_DEF asd WITH (NOLOCK) 
                       ON (sm.CUR_ACAD_PROBATION = asd.ACAD_STAND_CODE)),
 cte_newstu
     AS (SELECT 
				--'NEW'                                   grp, --for debugging
                ''                              PATIENT_CONTROL_ID,
                '' ssn,
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
                ''										WORK_PHONE,
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
                '7'                                     Employment,
                ''										Employer_Code,
                eml.alternatecontact                    EMAIL_ADDRESS,
                CASE
                  WHEN sdm.trm_hrs_attempt = 0 THEN 1
                  ELSE 2 --eligible
                END                                     Eligibility,
                CASE
                  WHEN loa.id_num IS NULL THEN 0
                  ELSE 1
                END                                     Inactive,
                CASE
                  WHEN ssa.room_assign_sts = 'A'
                THEN ra.bldg_cde + ra.room_cde
                  ELSE ''
                END                                     CAMPUS_ADDRESS,
                LEFT(amc.addr_line_1, 40)               PERMANENT_ADDRESS,
                amc.city                                PERMANENT_CITY,
                amc.state                               PERMANENT_STATE,
                amc.postalcode                          PERMANENT_ZIP_CODE,
                tdc.table_desc                          PERMANENT_COUNTRY,
                pm2.phone                               PERMANENT_PHONE,
                CASE
                  WHEN bm.citizen_of <> 'US' THEN 1
                  ELSE 0
                END                                     FOREIGN_STUDENT,
                bm.visa_type,
                CASE
                  WHEN dh.div_cde = 'UG'
                       AND sdm.trm_hrs_attempt >= 12 THEN
                  'Undergraduate Full Time'
                  WHEN dh.div_cde = 'UG'
                       AND sdm.trm_hrs_attempt > 0 THEN
                  'Undergraduate Part Time'
                  WHEN dh.div_cde = 'UG' THEN 'Undergraduate Not Registered'
                  WHEN dh.div_cde = 'GR'
                       AND sdm.trm_hrs_attempt >= 8 THEN 'Graduate Full Time'
                  WHEN dh.div_cde = 'GR'
                       AND sdm.trm_hrs_attempt > 0 THEN 'Graduate Part Time'
                  WHEN dh.div_cde = 'GR' THEN 'Graduate Not Registered'
                  WHEN dh.div_cde = 'CE' THEN 'Continuing Education'
                  ELSE 'Unknown'
                END                                     STANDING,
                can.class,
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
                LEFT(am.addr_line_2, 40)                AS ADDRESS_LINE_2,
                LEFT(amc.addr_line_2, 40)               AS
                PERMANENT_ADDRESS_LINE_2,
                alt_ctc.username                        NETWORK_USER_NAME,
                bmu.card_no                             MACKCARD_ID,
                dd.div_desc                             PROGRAM,
                sch.table_desc                          Subprogram,
                maj1.major_minor_desc                   MAJOR1,
                maj2.major_minor_desc                   MAJOR2,
                conc1.conc_desc                         CONC1,
                conc2.conc_desc                         CONC2,
                min1.major_minor_desc                   MINOR1,
                min2.major_minor_desc                   MINOR2,
                'ACPT-Accepted Full'                                 ACADEMIC_STATUS,
                loa.absence_desc                        LEAVE_REASON,
                loa.leave_begin_dte                     LEAVE_DATE
         -- -- -- -- -- -- -- -- -- -- -- -- --
         FROM   namemaster nm WITH (nolock)
                JOIN biograph_master bm WITH (nolock)
                  ON nm.id_num = bm.id_num
                JOIN cte_reg_stu rs
                  ON nm.id_num = rs.id_num
                JOIN cte_can can
                  ON nm.id_num = can.id_num
                JOIN cte_alt_ctc alt_ctc WITH (nolock)
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
                LEFT JOIN cte_loa loa
                       ON nm.id_num = loa.id_num
                LEFT JOIN degree_history dh WITH (nolock)
                       ON ( nm.id_num = dh.id_num
                            AND dh.cur_degree = 'Y' )
                LEFT JOIN student_div_mast sdm WITH (nolock)
                       ON ( dh.id_num = sdm.id_num
                            AND dh.div_cde = sdm.div_cde
                            AND sdm.is_student_div_active = 'Y' )
                LEFT JOIN student_master sm WITH (nolock)
                       ON ( sm.id_num = nm.id_num )
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
                       ON maj1.institut_div_cde = idd.institut_div_cde
                LEFT JOIN table_detail sch WITH (nolock)
                       ON idd.school_cde = sch.table_value
                          AND sch.column_name = 'SCHOOL_CDE'
                LEFT JOIN major_minor_def maj2 WITH (nolock)
                       ON ( dh.major_2 = maj2.major_cde )
                LEFT JOIN major_minor_def min1 WITH (nolock)
                       ON ( dh.minor_1 = min1.major_cde )
                LEFT JOIN major_minor_def min2 WITH (nolock)
                       ON ( dh.minor_2 = min2.major_cde )
                LEFT JOIN concentration_def conc1 WITH (nolock)
                       ON ( dh.concentration_1 = conc1.conc_cde )
                LEFT JOIN concentration_def conc2 WITH (nolock)
                       ON ( dh.concentration_2 = conc2.conc_cde ))
-- end of CTE specifications
SELECT  *
FROM   cte_curstu curstu
UNION
SELECT *
FROM   cte_newstu newstu 
order by other_id
;

    set nocount off;
    REVERT
END

;
GO
