SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[MCM_GetAdvocateStudentry]
    @daysago as int = 1
WITH EXECUTE AS 'dbo'
AS
-- =============================================
-- Author:		Will Trillich (Serensoft)	
-- Create date: 9/12/2024
-- Description:	Generate Symplicity ADVOCATE export data
-- Modified:
--	
-- =============================================
BEGIN
        set nocount on;

        -- declare @daysago int = 800; -- for debugging/exploratoria

        declare @cterm as varchar(6) = dbo.MCM_FN_CALC_TRM('CF') -- "current fall"
        declare @curyr as int        = cast(left(@cterm,4) as int);
        declare @nterm as varchar(6) = dbo.MCM_FN_CALC_TRM('CS') -- "current spring"
        declare @nxtyr as int        = cast(left(@nterm,4) as int);

        print @cterm + ':' + @nterm;


        SET @cterm = right(@cterm,2); -- SS
        set @nterm = right(@nterm,2);
        -- print 'terms='+@cterm+'/'+@nterm+', yrs=['+cast(@curyr as char(4))+','+cast(@nxtyr as char(4))+']';

WITH
cte_stu_population
    AS (
        -- declare @curyr int = 2023;
        -- declare @cterm varchar(2) = 'FA';
        -- declare @nxtyr int = 2023;
        -- declare @nterm varchar(2) = 'SP';

        SELECT DISTINCT
                ID_NUM
        FROM    student_crs_hist sch
        WHERE   stud_div IN ( 'UG', 'GR' )
                AND (
                    ( YR_CDE = @curyr and TRM_CDE = @cterm )
                    OR
                    ( YR_CDE = @nxtyr and TRM_CDE = @nterm )
                )
                AND transaction_sts IN ( 'C', 'D' )
                AND JOB_TIME > getdate() - @daysago
    )
    ,
cte_loa
    AS (
        SELECT DISTINCT x.id_num,
                        x.leave_begin_dte,
                        x.absence_cde,
                        d.absence_desc
        FROM
            leaveofabsence x
        JOIN
            cte_stu_population stu
                ON x.ID_NUM = stu.ID_NUM
        LEFT JOIN
            absence_def d WITH (nolock)
                ON ( x.absence_cde = d.absence_cde )
        WHERE  ( x.leave_begin_dte <= Getdate()
           AND ( x.leave_end_dte IS NULL OR x.leave_end_dte > Getdate() ) )
    )
    ,
cte_sport
    AS (
        SELECT DISTINCT st.id_num
        FROM SPORTS_TRACKING st
            join
            cte_stu_population stu
            on st.ID_NUM = stu.ID_NUM
        WHERE
            (st.YR_CDE = @curyr and st.TRM_CDE = @cterm)
            or
            (st.YR_CDE = @nxtyr and st.TRM_CDE = @nterm)
    )
    ,
cte_info
    AS  (
        select
            nm.ID_NUM,
            nm.FIRST_NAME,
            nm.LAST_NAME,
            am.ADDR_LINE_1,
            am.ADDR_LINE_2,
            am.CITY,
            am.STATE,
            am.postalcode ZIP,
            pm.PHONE,
            CONVERT(VARCHAR(10), bm.birth_dte, 101)     BIRTH_DATE,
            bm.GENDER,
            dh.MAJOR_1,
            dh.MINOR_1,
            sdm.CAREER_GPA
        FROM
        cte_stu_population stu
        JOIN
        namemaster nm
            on nm.ID_NUM = stu.ID_NUM
        LEFT JOIN
        biograph_master bm WITH (nolock)
            ON stu.id_num = bm.id_num
        LEFT JOIN
        degree_history dh WITH (nolock)
            ON ( dh.id_num = stu.id_num
                AND dh.cur_degree = 'Y' )
        LEFT JOIN student_div_mast sdm WITH (nolock)
            ON ( dh.id_num = sdm.id_num
                AND dh.div_cde = sdm.div_cde
                AND sdm.is_student_div_active = 'Y' )
        LEFT JOIN
        nameaddressmaster nam WITH (nolock)
            ON nm.id_num = nam.id_num
                AND nam.addr_cde = '*LHP' --*LHP address
        LEFT JOIN
        addressmaster am WITH (nolock)
            ON nam.addressmasterappid = am.appid
        LEFT JOIN
        namephonemaster npm WITH (nolock)
            ON nm.appid = npm.namemasterappid
                AND npm.phonetypedefappid = -16 --mobile phone
        LEFT JOIN
        phonemaster pm WITH (nolock)
            ON npm.phonemasterappid = pm.appid
-- where dh.ID_NUM is null -- "shouldn't happen"
    )
    ,
cte_dorm
    as (
        SELECT
            ra.id_num,
            ra.bldg_cde,
            ra.room_cde
        FROM
            ROOM_ASSIGN ra
            join
            cte_stu_population stu
                on ra.ID_NUM = stu.ID_NUM
        WHERE
            sess_cde in (
                @cterm + cast(@curyr as char(4)),
                @nterm + cast(@nxtyr as char(4))
            )
    )
    ,
cte_emails
    as (
        select
            eml.ID_NUM,
            max(case when ADDR_CDE = '*EML' then AlternateContact else '' end) email1,
            max(case when ADDR_CDE = 'PEML' then AlternateContact else '' end) email2
        from
            AlternateContactMethod eml
            join
            cte_stu_population stu
            on eml.ID_NUM = stu.ID_NUM
        group by
            eml.id_num
    )

SELECT
    bio.id_num          ID,
    bio.FIRST_NAME      FIRSTNAME,
    bio.LAST_NAME       LASTNAME,
    eml.email1          EMAIL,
    eml.email2          EML2,
    dorm.BLDG_CDE       BLDG,
    dorm.ROOM_CDE       ROOM,
    bio.BIRTH_DATE,
    bio.GENDER,
    bio.CAREER_GPA      GPA,
    bio.ADDR_LINE_1     ADDR_1,
    bio.ADDR_LINE_2     ADDR_2,
    bio.CITY            CITY,
    bio.[STATE]         STATE,
    bio.ZIP             ZIP,
    bio.PHONE           PHONE,
    sm.current_class_cde    CLASS,
    bio.MAJOR_1         MAJOR,
    bio.MINOR_1         MINOR,
    case when sport.id_num is null then 'NO' else 'YES' end
                        ATHLETE,
    -- CASE
    --     WHEN loa.ID_NUM IS NOT NULL AND dh.EXIT_REASON IS NULL THEN loa.ABSENCE_CDE + '-' + loa.ABSENCE_DESC 
    --     WHEN dh.EXIT_REASON IS NOT NULL THEN dh.EXIT_REASON + '-' + ext.TABLE_DESC
    --     WHEN sm.CUR_ACAD_PROBATION IS NOT NULL THEN sm.CUR_ACAD_PROBATION + '-' + asd.ACAD_STAND_DESC
    --     WHEN sm.CURRENT_CLASS_CDE = 'NM' THEN 'NM-Non_Matriculate'
    --     ELSE ''
    -- END                 REASON,
    CONVERT(varchar(10), loa.leave_begin_dte, 101)
                        LEAVE_DATE,
    loa.absence_desc    REASON

FROM
    cte_info bio
    JOIN
    student_master sm WITH (nolock)
        ON ( sm.id_num = bio.id_num )
    -- LEFT JOIN
    -- ACAD_STANDING_DEF asd WITH (NOLOCK) 
    --     ON (sm.CUR_ACAD_PROBATION = asd.ACAD_STAND_CODE)
    -- LEFT JOIN
    -- (
    -- degree_history dh WITH (nolock)
    -- LEFT JOIN
    -- TABLE_DETAIL ext WITH (NOLOCK) 
    --     ON dh.EXIT_REASON = ext.TABLE_VALUE AND ext.COLUMN_NAME = 'exit_reason'
    -- )
    --     ON ( bio.id_num = bio.id_num
    --         AND dh.cur_degree = 'Y' )
    LEFT JOIN
    cte_loa loa
        on bio.ID_NUM = loa.ID_NUM
    LEFT JOIN
    cte_sport sport
        on bio.ID_NUM = sport.ID_NUM
    LEFT JOIN
    cte_dorm dorm
        on bio.ID_NUM = dorm.ID_NUM
    LEFT JOIN
    cte_emails eml
        on bio.ID_NUM = eml.ID_NUM
-- where sm.CURRENT_CLASS_CDE not in ('FR','GR')
;


    set nocount off;
    REVERT
END

;
GO
