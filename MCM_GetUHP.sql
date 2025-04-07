
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[MCM_GetUHP](
    @fakenews int = 0
)

WITH EXECUTE AS 'dbo'
AS
-- =============================================
-- Author:		Will Trillich (Serensoft)	
-- Create date: 3/25/2025
-- Description:	UHP extract
    /*
        On CX we had a custom table UHP_CAL_REC to determine when to start/stop
        processing for each semester, independent of start/stop dates for the actual
        semesters. Here we can use REG_CONFIG for current yr/term until we learn of
        something better.

        On CX we had custom CTC_REC.RESRC codes to INCLUDE-student-regardless and
        other custom CTC_REC.RESRC codes to EXCLUDE-student-regardless. For now we
        are only implementing the regular logic here.
    */
-- Modified:	

-- =============================================
BEGIN

declare @curyr char(4);
declare @cterm varchar(6);

select
    @curyr = cur_yr_dflt,
    @cterm = cur_trm_dflt 
from
    reg_config;

declare @term_code varchar(6) = @cterm + @curyr;

WITH
cte_reg_pool AS (
    -- active courses for current semester
    SELECT DISTINCT
        ID_NUM, -- student
        CRS_CDE,
        TRM_CDE,
        YR_CDE
    FROM
        STUDENT_CRS_HIST crs
    WHERE   stud_div IN ( 'UG', 'GR' )
        AND YR_CDE = @curyr
        AND TRM_CDE = @cterm
        AND TRANSACTION_STS IN ( 'H', 'C', 'D' )
)
,

cte_reg_crs as (
    -- just the courses so we can find the faculty
    SELECT DISTINCT
        CRS_CDE,
        TRM_CDE,
        YR_CDE
    FROM
        cte_reg_pool
)
,

cte_fac as (
    -- faculty for currrent courses
    SELECT DISTINCT
        fl.INSTRCTR_ID_NUM
    FROM
        FACULTY_LOAD_TABLE fl with (nolock)
        JOIN
        cte_reg_crs rc with (nolock)
        on (fl.CRS_CDE = rc.CRS_CDE and fl.YR_CDE = rc.YR_CDE and fl.TRM_CDE = rc.TRM_CDE)
)
,

cte_reg_stu as (
    -- students for current courses
    SELECT DISTINCT
        crs.ID_NUM
    FROM
        cte_reg_pool crs
    WHERE
        -- omit/exclude faculty
        crs.ID_NUM not in ( select INSTRCTR_ID_NUM from cte_fac )
)
-- select * from cte_reg_stu;
,

cte_sport AS (
    -- find the athletix
    SELECT DISTINCT
        ID_NUM
    from
        SPORTS_TRACKING WITH (nolock)
    where
        YR_CDE  = @curyr and
        TRM_CDE = @cterm and
        id_num in ( select id_num from cte_reg_stu )
)
-- select * from cte_sport;
,
cte_online as (
    -- find the online students
    SELECT
        id_num,
        UDEF_1A_4               online
    FROM
        STUDENT_MASTER WITH (nolock)
    WHERE
        UDEF_1A_4 > ''
        and
        id_num in ( select id_num from cte_reg_stu ) -- FIXME?
        -- primary key for student_master involves FOUR fields: 
        --  id_num
        --  degr_hist_seq_num
        --  current_class_cde
        --  cur_stud_div
)
,

cte_bio as (
    -- get the bio/demographic info
    SELECT DISTINCT
        stu.ID_NUM              SID,
        nm.FIRST_NAME,
        nm.LAST_NAME,
        bm.BIRTH_DTE            DATE_OF_BIRTH,
        bm.GENDER,
        am.ADDR_LINE_1          ADDRESS_1,
        am.ADDR_LINE_2          ADDRESS_2,
        am.CITY,
        am.[STATE],
        am.ZIP5 + case when am.ZIP4 > ''
            then '-' + am.ZIP4
            else ''
            end                 ZIP,
        acm.AlternateContact    EMAIL,
        case when bm.visa_type>'' and am.COUNTRY<>'USA'
            then 'Y'
            else ''
            end                 INTERNATIONAL_STUDENT_INDICATOR,
        @term_code              TERM_CODE,
        case when sp.ID_NUM is not null
            then 'Y'
            else ''
            end                 ATHLETE,
        case when am.[STATE] = 'MA'
            then 'N'
            else 'Y'
            end                 OUT_OF_STATE_INDICATOR,
        ol.[online]             ONLINE,
        '' x

    FROM
        cte_reg_stu stu -- only these students (omitting faculty)
        JOIN
        NameMaster nm with (nolock)
            on (stu.ID_NUM = nm.ID_NUM)
        JOIN
        BIOGRAPH_MASTER bm with (nolock)
            on (nm.id_num = bm.id_num)
        LEFT JOIN
        nameaddressmaster nam WITH (nolock)
            ON nm.id_num = nam.id_num
                AND nam.addr_cde = '*LHP' --*LHP address
        LEFT JOIN
        addressmaster am WITH (nolock)
            ON (nam.addressmasterappid = am.appid)
        LEFT JOIN
        AlternateContactMethod acm with (nolock)
            ON (nm.ID_NUM = acm.ID_NUM and acm.ADDR_CDE = '*EML')
        LEFT JOIN
        cte_sport sp with (nolock)
            on (nm.ID_NUM = sp.ID_NUM)
        LEFT JOIN
        cte_online ol with (nolock)
            on (nm.ID_NUM = ol.ID_NUM)

)

-- select count(*) from (
SELECT 
    bio.SID,
    bio.FIRST_NAME,
    bio.LAST_NAME,
    bio.DATE_OF_BIRTH,
    bio.GENDER,
    bio.ADDRESS_1,
    bio.ADDRESS_2,
    bio.CITY,
    bio.[STATE],
    bio.ZIP,
    bio.EMAIL,
    bio.INTERNATIONAL_STUDENT_INDICATOR,
    bio.TERM_CODE,
    bio.ATHLETE,
    bio.OUT_OF_STATE_INDICATOR,
    bio.ONLINE
FROM
    cte_bio bio
ORDER BY
    bio.sid,
    bio.LAST_NAME,
    bio.FIRST_NAME
-- ) x
    ;


    set nocount off;
    REVERT
END

;
GO

