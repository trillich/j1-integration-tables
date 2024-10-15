SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[MCM_GetASC_stuAcadDaily]
    @exec as bit = 1
WITH EXECUTE AS 'dbo'
AS
-- =============================================
-- Author:		Will Trillich (Serensoft)	
-- Create date: 10/11/2024
-- Description:	Generate ASC exam export for slate
-- Modified:	
-- =============================================
BEGIN
     set nocount on;

        declare @cterm as VARCHAR(6) = '2024FA'; -- for debugging
        -- set @cterm = dbo.MCM_FN_CALC_TRM('C');
        declare @curyr as INT        = cast(left(@cterm,4) as int);
        -- declare @nxtyr as INT        = @curyr + 1;
        -- declare @prvyr as INT        = @curyr - 1;

        -- declare @pterm as VARCHAR(6) = '2023SP'; -- for debugging
        -- set @pterm = dbo.MCM_FN_CALC_TRM('P');
        -- declare @pyr   as INT        = cast(left(@pterm,4) as int);

        -- print @cterm +'/'+ cast(@curyr as varchar)

        SET @cterm = right(@cterm,2);
        -- print concat('cterm=',@cterm,', yrs=[',@prvyr,',',@curyr,',',@nxtyr,']: pterm=',@pterm);
        -- SET @pterm = right(@pterm,2);

-- [JZMCM-SQL].[J1TEST].[dbo]. <== table prefix for LIVE-ish database
-- select count(*) from namemaster;
-- select count(*) from [JZMCM-SQL].[J1TEST].[dbo].namemaster;

WITH
cte_pop as (
	--Just retrieve the unique population of ID's that match the previous, current and next academic years
	SELECT DISTINCT
            sm.ID_NUM,
            dh.DIV_CDE
	 FROM
            STUDENT_MASTER sm WITH (nolock)
            JOIN
            DEGREE_HISTORY dh WITH (nolock)
                on sm.ID_NUM = dh.ID_NUM
	 WHERE sm.id_num in (
                SELECT distinct id_num
                FROM STUDENT_CRS_HIST sch
                WHERE stud_div IN ( 'UG', 'GR' )
                AND sch.YR_CDE in (2024) -- (@curyr)
                AND sch.transaction_sts IN ( 'H', 'C', 'D' )
        )
            AND sm.CURRENT_CLASS_CDE NOT IN ( 'CE','NM','AV' )
            AND dh.MAJOR_1 <> 'GEN' -- omit nonmatric
            AND dh.cur_degree = 'Y'
)
,
cte_slateids as (
    SELECT
        ID_NUM,
        max(case when IDENTIFIER_TYPE='SUG' then IDENTIFIER else null end) SUG,
        max(case when IDENTIFIER_TYPE='SGPS' then IDENTIFIER else null end) SGPS
    FROM
        ALTERNATE_IDENTIFIER ai WITH (nolock)
    WHERE
        ai.ID_NUM in ( select ID_NUM from cte_pop )
        and ai.IDENTIFIER_TYPE in ('SUG','SGPS') -- FIXME no SGPS data in J1CONV, need to confirm with real data
        and (ai.BEGIN_DTE is null or ai.BEGIN_DTE <= getdate())
        and (ai.END_DTE is null or ai.END_DTE > getdate())
    GROUP BY ID_NUM
)
-- select * from cte_slateids where sgps > '!';
,

cte_acad as (
    SELECT
        pop.ID_NUM,
        dh.DIV_CDE                          prog_code,
        dd.div_desc                         prog_desc,
        'FIXME'                             subprog_desc,
        cd.CLASS_DESC                       cl_desc,
        sm.ENTRANCE_TRM + sm.ENTRANCE_YR    admit_sessyr,
        sm.ENTRANCE_YR                      admit_yr,
        sdm.ENTRY_DTE                       enr_date,
        case when dh.DIV_CDE not in ('NM','GNM') then sdm.ENTRY_DTE else null end
                                            matric_date,
        'FIXME'                             acst_desc, -- academic status in CX
        'FIXME'                             acst_code,
        dh.MAJOR_1                          major1_code,
        maj1.MAJOR_MINOR_DESC               major1_desc,
        dh.MAJOR_2                          major2_code,
        maj2.MAJOR_MINOR_DESC               major2_desc,
        dh.MAJOR_3                          major3_code,
        maj3.MAJOR_MINOR_DESC               major3_desc,
        dh.CONCENTRATION_1                  conc1_code,
        cd1.conc_desc                       conc1_desc,
        dh.CONCENTRATION_2                  conc2_code,
        cd2.conc_desc                       conc2_desc,
        dh.MINOR_1                          minor1_code,
        min1.MAJOR_MINOR_DESC               minor1_desc,
        dh.MINOR_2                          minor2_code,
        min2.MAJOR_MINOR_DESC               minor2_desc,
        dh.MINOR_3                          minor3_code,
        min3.MAJOR_MINOR_DESC               minor3_desc,
        dh.DEG_APPLICATION_DTE              deg_app_date,
        dh.EXPECT_GRAD_TRM + dh.EXPECT_GRAD_YR
                                            plan_grad_sessyr,
        'FIXME'                             currenr_code,
        'FIXME'                             currenr_desc,
        'FIXME'                             entrtype_code,
        'FIXME'                             entrtype_desc,
        sdm.TRANSFER_IN                     transfer,
        case when hon.ID_NUM > 0 then 'Y' else 'N' end
                                            honors,
        sdm.CAREER_HRS_ATTEMPT              cum_att_hrs,
        sdm.CAREER_HRS_EARNED               cum_earn_hrs,
        sdm.CAREER_GPA                      cum_gpa
    FROM
        cte_pop pop
        JOIN
        STUDENT_MASTER sm WITH (nolock)
            on (pop.ID_NUM = sm.ID_NUM )
        JOIN
        DEGREE_HISTORY dh WITH (nolock)
            on (pop.ID_NUM = dh.ID_NUM 
                and pop.DIV_CDE = dh.DIV_CDE
                and CUR_DEGREE = 'Y' -- FIXME do we need this in a CASE statement instead?
            )
        JOIN
        STUDENT_DIV_MAST sdm WITH (nolock)
            ON ( dh.id_num = sdm.id_num
                AND dh.div_cde = sdm.div_cde
                AND sdm.is_student_div_active = 'Y'
            )
        JOIN
        DIVISION_DEF dd WITH (nolock)
            ON ( pop.DIV_CDE = dd.DIV_CDE )
        LEFT JOIN
        CLASS_DEFINITION cd
            ON ( sdm.CLASS_CDE = cd.CLASS_CDE )
        LEFT JOIN
        MAJOR_MINOR_DEF maj1 WITH (nolock)
            on ( dh.MAJOR_1 = maj1.MAJOR_CDE )
        LEFT JOIN
        MAJOR_MINOR_DEF maj2 WITH (nolock)
            on ( dh.MAJOR_2 = maj2.MAJOR_CDE )
        LEFT JOIN
        MAJOR_MINOR_DEF maj3 WITH (nolock)
            on ( dh.MAJOR_3 = maj3.MAJOR_CDE )
        LEFT JOIN
        CONCENTRATION_DEF cd1 WITH (nolock)
            on ( dh.concentration_1 = cd1.conc_cde )
        LEFT JOIN
        CONCENTRATION_DEF cd2 WITH (nolock)
            on ( dh.concentration_2 = cd2.conc_cde )
        LEFT JOIN
        MAJOR_MINOR_DEF min1 WITH (nolock)
            on ( dh.MINOR_1 = min1.MAJOR_CDE )
        LEFT JOIN
        MAJOR_MINOR_DEF min2 WITH (nolock)
            on ( dh.MINOR_2 = min2.MAJOR_CDE )
        LEFT JOIN
        MAJOR_MINOR_DEF min3 WITH (nolock)
            on ( dh.MINOR_3 = min3.MAJOR_CDE )
        LEFT JOIN
        ATTRIBUTE_TRANS hon WITH (nolock)
            on ( pop.ID_NUM = hon.ID_NUM
                and hon.ATTRIB_CDE = 'HON'
                and hon.ATTRIB_BEGIN_DTE <= getdate()
                -- FIXME should this be linked via sess/yr?
            )
)
-- select * from cte_acad where conc2_code>'!';

SELECT
    slate.SUG                       slate_id,
    slate.SGPS                      slate_guid_asc,
    pop.ID_NUM                      cx_id,
    prog_code,
    prog_desc,
    subprog_desc,
    cl_desc,
    admit_sessyr,
    admit_yr,
    enr_date,
    matric_date,
    acst_desc,
    acst_code,
    major1_code,
    major1_desc,
    major2_code,
    major2_desc,
    major3_code,
    major3_desc,
    conc1_code,
    conc1_desc,
    conc2_code,
    conc2_desc,
    minor1_code,
    minor1_desc,
    minor2_code,
    minor2_desc,
    minor3_code,
    minor3_desc,
    deg_app_date,
    plan_grad_sessyr,
    prim_adv,
    prim_adv_email,
    sec_adv,
    sec_adv_email,
    career_adv,
    career_adv_email,
    leave_reason,
    leave_date,
    'FIXME'                         online,
    currenr_code,
    currenr_desc,
    entrtype_code,
    entrtype_desc,
    honors,
    transfer,
    'FIXME'                         adm_hsg_type,
    'FIXME'                         adm_plansessyr,
    'FIXME'                         adm_withpaid,
    'FIXME'                         degree_earn,
    'FIXME'                         degree_sessyr,
    cum_att_hrs,
    cum_earn_hrs,
    cum_gpa
FROM
    cte_pop pop
    JOIN
    cte_acad acad
    on (pop.ID_NUM=acad.ID_NUM and pop.DIV_CDE=acad.prog_code)
    LEFT JOIN
    cte_adv adv
    on (pop.ID_NUM=adv.ID_NUM)
    LEFT JOIN
    cte_loa loa
    on (pop.ID_NUM=loa.ID_NUM)
    LEFT JOIN
    cte_slateids slate
    on (pop.ID_NUM=slate.ID_NUM)
ORDER BY
    pop.ID_NUM, pop.DIV_CDE;

    set nocount off;
    REVERT
END

;
GO
