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

        declare @cterm as VARCHAR(6) = '2024FA'; -- for debugging
        set @cterm = dbo.MCM_FN_CALC_TRM('C');
        declare @curyr as INT        = cast(left(@cterm,4) as int);
        declare @nxtyr as INT        = @curyr + 1;
        declare @prvyr as INT        = @curyr - 1;

        declare @pterm as VARCHAR(6) = '2023SP'; -- for debugging
        set @pterm = dbo.MCM_FN_CALC_TRM('P');
        declare @pyr   as INT        = cast(left(@pterm,4) as int);

        -- print @cterm +'/'+ cast(@curyr as varchar)

        SET @cterm = right(@cterm,2);
        -- print concat('cterm=',@cterm,', yrs=[',@prvyr,',',@curyr,',',@nxtyr,']: pterm=',@pterm);
        SET @pterm = right(@pterm,2);

-- [JZMCM-SQL].[J1TEST].[dbo]. <== table prefix for LIVE-ish database
-- select count(*) from namemaster;
-- select count(*) from [JZMCM-SQL].[J1TEST].[dbo].namemaster;

WITH
cte_reg_stu
     AS (
        SELECT DISTINCT
            sm.id_num,
            sm.current_class_cde    ClassStanding,
            dh.MAJOR_1              Major,
            dh.MINOR_1              Minor,
            dh.DEGR_CDE             DegreeSought,
            td.TABLE_DESC           PrimarySchoolOfEnrollment,
            cd.COHORT_DESC,
            case
                when sdm.EXPECTED_GRAD_TRM = 'WI'
                then '12/31/' + cast(sdm.EXPECTED_GRAD_YR as char(4))
                when sdm.EXPECTED_GRAD_TRM = 'SU'
                then '8/31/' + cast(sdm.EXPECTED_GRAD_YR as char(4))
                else '5/31/' + cast(sdm.EXPECTED_GRAD_YR as char(4))
                END                 AnticipatedDateOfGraduation,
            dd.DIV_DESC             CareerLevel,
            case sdm.TRANSFER_IN
            when 'Y'
            then 'True'
            else 'False'
            END                     Transfer
        FROM
            STUDENT_MASTER sm WITH (nolock)
            JOIN
            DEGREE_HISTORY dh WITH (nolock)
                on sm.ID_NUM = dh.ID_NUM
            JOIN
            STUDENT_DIV_MAST sdm WITH (nolock)
                on sm.id_num = sdm.id_num
            LEFT JOIN
            DIVISION_DEF dd WITH (nolock)
                on sdm.DIV_CDE = dd.DIV_CDE
            LEFT JOIN
            COHORT_DEFINITION cd WITH (nolock)
                on sdm.COHORT_DEFINITION_APPID = cd.APPID
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
        WHERE sm.id_num in (
                SELECT distinct id_num
                FROM STUDENT_CRS_HIST sch
                WHERE stud_div IN ( 'UG', 'GR' )
                AND sch.YR_CDE in (@prvyr,@curyr,@nxtyr)
                AND sch.transaction_sts IN ( 'H', 'C', 'D' )
        )
            AND sm.CURRENT_CLASS_CDE NOT IN ( 'CE','NM','AV' )
            AND dh.MAJOR_1 <> 'GEN' -- omit nonmatric
            AND dh.cur_degree = 'Y'
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
        NameMaster nm WITH (nolock)
            LEFT JOIN
        AlternateNameMasterNames anmn WITH (nolock)
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
            BIOGRAPH_MASTER bm WITH (nolock)
            LEFT JOIN
            BIOGRAPH_MASTER_UDF bmu WITH (nolock)
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
        SELECT DISTINCT
            ID_NUM
        from
            SPORTS_TRACKING WITH (nolock)
        where
            yr_cde=@curyr and
            TRM_CDE = @cterm and
            id_num in ( select id_num from cte_reg_stu )
    )
-- select * from cte_sport;
    ,
cte_phones
    as (
        SELECT
            n.ID_NUM,
            max(pm_mobile.PHONE)         MobilePhone,
            max(pm_home.PHONE)           HomePhone
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
        GROUP BY
            id_num
    )
-- select * from cte_phones -- where HomePhone<>MobilePhone
    ,
cte_gpa_detail
    as (
        SELECT
            ID_NUM,
            TRM_CDE,
            YR_CDE,
            format(TRM_GPA,'0.000') gpa
        FROM
            STUD_TERM_SUM_DIV WITH (nolock)
        WHERE
            id_num in ( select id_num from cte_reg_stu )
            and
            (
                (YR_CDE = @pyr and TRM_CDE = @pterm)
                OR
                (YR_CDE = @curyr and TRM_CDE = @cterm)
            )
    )
-- select * from cte_gpa_detail;
    ,
cte_gpa
    as (
        SELECT
            ID_NUM,
            max(
                case when TRM_CDE = @pterm then gpa else null end
            )   PreviousTermGPA,
            max(
                case when TRM_CDE = @cterm then gpa else null end
            )   CurrentTermGPA
        FROM
            cte_gpa_detail WITH (nolock)
        GROUP BY
            ID_NUM
    )
-- select * from cte_gpa order by id_num;
    ,
cte_res
    as (
        SELECT
            ssa.ID_NUM,
            ra.bldg_cde,
            ra.room_cde,
            case
                when RESID_COMMUTER_STS = 'R'
                then 'Resident'
                when RESID_COMMUTER_STS = 'C'
                then 'Commuter'
                when RESID_COMMUTER_STS = 'L'
                then 'Commuter/Lease'
                when RESID_COMMUTER_STS = 'F'
                then 'Commuter/Family'
                when RESID_COMMUTER_STS = 'W'
                then 'Withdrawn'
                else RESID_COMMUTER_STS + '?'
                END         LocalResidencyStatus,
            rm.ROOM_DESC
        FROM
            STUD_SESS_ASSIGN ssa
            left join
            ROOM_ASSIGN ra
                on ssa.SESS_CDE = ra.SESS_CDE and ssa.ID_NUM = ra.ID_NUM
            left join
            ROOM_MASTER rm
                on rm.BLDG_CDE = ra.BLDG_CDE and rm.ROOM_CDE = ra.ROOM_CDE
        WHERE
            ssa.ID_NUM in ( select id_num from cte_reg_stu )
            AND
            ssa.SESS_CDE = concat(@cterm,@curyr)
    )

select
    'Overwrite'                     Action,
    email.username                  Username,
    names.InstitutionProvidedFirstName,
    names.InstitutionProvidedLastName,
    names.InstitutionProvidedMiddleName,
    names.LegalFirstName,
    names.LegalLastName,
    names.Suffix,
    email.email                     CampusEmail,
    peml.peml                       PreferredEmail,
    bio.CardID,
    bio.ID_NUM                      SISID,
    ''          Hometown,
    'Student'                       Affiliation,
    phones.MobilePhone,
    bio.DateOfBirth,
    bio.Sex,
    bio.Race,
    bio.Ethnicity,
    stu.COHORT_DESC                 EnrollmentStatus,
    ''                              CurrentTermEnolled,
    gpa.CurrentTermGPA,
    ''                              PreviousTermEnrolled,
    gpa.PreviousTermGPA,
    ''                              CreditHoursEarned,
    stu.AnticipatedDateOfGraduation,
    stu.CareerLevel,
    stu.ClassStanding,
    stu.PrimarySchoolOfEnrollment,
    stu.DegreeSought,
    stu.Major,
    stu.Minor,
    ''          MajorAdvisor,
    ''          OtherAdvisor,
    res.LocalResidencyStatus,
    res.ROOM_DESC                   HousingFacility,
    International,
    stu.Transfer,
    case when sport.ID_NUM is null then 'False' else 'True' end
                                    Athlete,
    ''                              AthleticParticipation,
    ''                              LocalPhoneCountryCode,
    ''                              LocalPhone,
    ''                              LocalPhoneExtension,
    ''                              LocatStreet1,
    ''                              LocalStreet2,
    ''                              LocalStreet3,
    ''                              LocalCity,
    ''                              LocalStateProvince,
    ''                              LocalPostalCode,
    ''                              LocalCountry,
    ''                              HomePhoneCountryCode,
    ''                              HomePhone,
    ''                              HomePhoneExtension,
    ''                              HomeStreet1,
    ''                              HomeStreet2,
    ''                              HomeStreet3,
    ''                              HomeCity,
    ''                              HomeStateProvince,
    ''                              HomePostalCode,
    ''                              HomeCountry,
    ''                              AbroadPhoneCountryCode,
    ''                              AbroadPhone,
    ''                              AbroadPhoneExtension,
    ''                              AbroadStreet1,
    ''                              AbroadStreet2,
    ''                              AbroadStreet3,
    ''                              AbroadCity,
    ''                              AbroadStateProvince,
    ''                              AbroadPostalCode,
    ''                              AbroadCountry
from
    cte_reg_stu stu
    JOIN
    cte_bio bio
        on stu.ID_NUM = bio.ID_NUM
    JOIN
    cte_names names
        on bio.ID_NUM = names.ID_NUM
    LEFT JOIN
    cte_email email
        on bio.ID_NUM = email.ID_NUM
    LEFT JOIN
    cte_peml peml
        on bio.ID_NUM = peml.ID_NUM
    LEFT JOIN
    cte_gpa gpa
        on bio.ID_NUM = gpa.ID_NUM
    LEFT JOIN
    cte_phones phones
        on bio.ID_NUM = phones.ID_NUM
    LEFT JOIN
    cte_sport sport
        on bio.ID_NUM = sport.ID_NUM
    LEFT JOIN
    cte_res res
        on bio.ID_NUM = res.ID_NUM
-- where stu.id_num = 68431
-- where LegalFirstName <> InstitutionProvidedFirstName
-- where TRANSFER_IN = 'Y'
    ;

    set nocount off;
    REVERT
END

;
GO
