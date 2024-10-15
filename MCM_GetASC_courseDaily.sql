SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[MCM_GetASC_courseDaily]
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
            -- FIXME: past/present, do we want ALL students?
	--  WHERE sm.id_num in (
    --             SELECT distinct id_num
    --             FROM STUDENT_CRS_HIST sch
    --             WHERE stud_div IN ( 'UG', 'GR' )
    --             AND sch.YR_CDE in (@curyr)
    --             AND sch.transaction_sts IN ( 'H', 'C', 'D' )
    --     )
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
cte_fac_detail as (
    SELECT DISTINCT
        fl.CRS_CDE
        ,fl.INSTRCTR_ID_NUM
        ,nm.FIRST_NAME
        ,nm.LAST_NAME
        ,nm.FIRST_NAME + ' ' + nm.LAST_NAME fullname
        ,nm.LAST_NAME + ', ' + nm.FIRST_NAME alfaname
        ,acm.AlternateContact fac_email
        ,fl.TRM_CDE
        ,fl.YR_CDE
        -- FIXME: how should faculty/instructors be ranked/sequenced?
        ,DENSE_RANK() over (partition by fl.CRS_CDE order by fl.INSTRCTR_ID_NUM) ix
    FROM
        FACULTY_LOAD_TABLE fl with (nolock)
        JOIN
        NameMaster nm with (nolock)
        on nm.ID_NUM = fl.INSTRCTR_ID_NUM
        LEFT JOIN
        AlternateContactMethod acm with (nolock)
        on fl.INSTRCTR_ID_NUM = acm.ID_NUM and acm.ADDR_CDE = '*EML'
    WHERE
        nm.LAST_NAME not like 'TBA %'
        -- FIXME: do we want all years/terms? CX reached far into the past
        and fl.YR_CDE = @curyr
        and fl.TRM_CDE = left(@cterm,2)
)
-- select * from cte_fac;
,
cte_fac as (
    SELECT
        CRS_CDE,
        YR_CDE,
        TRM_CDE,

        max(case when ix=1 then INSTRCTR_ID_NUM else null end) fac1_id,
        max(case when ix=1 then fac_email else null end) fac1_email,
        max(case when ix=1 then FIRST_NAME else null end) fac1_fname,
        max(case when ix=1 then LAST_NAME else null end) fac1_lname,

        max(case when ix=2 then INSTRCTR_ID_NUM else null end) fac2_id,
        max(case when ix=2 then fac_email else null end) fac2_email,
        max(case when ix=2 then FIRST_NAME else null end) fac2_fname,
        max(case when ix=2 then LAST_NAME else null end) fac2_lname,

        max(case when ix=3 then INSTRCTR_ID_NUM else null end) fac3_id,
        max(case when ix=3 then fac_email else null end) fac3_email,
        max(case when ix=3 then FIRST_NAME else null end) fac3_fname,
        max(case when ix=3 then LAST_NAME else null end) fac3_lname
    FROM
        cte_fac_detail
    GROUP BY
        CRS_CDE,YR_CDE,TRM_CDE
)
-- select * from cte_fac;
,
cte_crs as (
    SELECT
        crs.ID_NUM,
        crs.STUD_DIV,
        crs.trm_cde + crs.yr_cde    cw_sessyr,
        crs.SUBTERM_CDE,
        crs.CRS_CDE,
        crs.crs_title,
        crs.TUITION_HRS,
        crs.GRADE_CDE,
        crs.MIDTERM_GRA_CDE,
        case -- FIXME just guessing on cw_stat here
            when crs.DROP_DTE is not null
            then 'D'
            when crs.WITHDRAWAL_DTE is not null
            then 'W'
            else 'R'
        END                         cw_stat,
        crs.REPEAT_FLAG,
        replace(crs.CRS_CDE,' ','')
            + '_'
            + replace(
                + crs.TRM_CDE
                + crs.YR_CDE
                + coalesce(crs.SUBTERM_CDE,'')
                ,' ','')            cw_unique_courseid,
        'FIXME'                     cw_crs_area
    FROM
        STUDENT_CRS_HIST crs
        JOIN
        cte_pop pop
            ON crs.ID_NUM = pop.ID_NUM and crs.STUD_DIV = pop.DIV_CDE
)
-- select * from cte_crs;

SELECT
    slate.SGPS,
    slate.SUG,
    pop.ID_NUM          cx_id,
    pop.DIV_CDE         cw_prog,
    crs.cw_sessyr,
    crs.SUBTERM_CDE     cw_subsess,
    crs.CRS_CDE         cw_crs_no,
    crs.CRS_TITLE       cw_crs_title,
    crs.cw_unique_courseid,
    crs.TUITION_HRS     cw_hrs,
    crs.GRADE_CDE       cw_final_grade,
    crs.MIDTERM_GRA_CDE cw_midterm_grade,
    crs.cw_stat,
    crs.REPEAT_FLAG     cw_crs_repeat,
    crs.cw_crs_area,
    fac.fac1_lname      cw_instr1_last,
    fac.fac1_fname      cw_instr1_first,
    fac.fac1_email      cw_instr1_email,
    fac.fac2_lname      cw_instr2_last,
    fac.fac2_fname      cw_instr2_first,
    fac.fac2_email      cw_instr2_email,
    fac.fac3_lname      cw_instr3_last,
    fac.fac3_fname      cw_instr3_first,
    fac.fac3_email      cw_instr3_email
FROM
    cte_pop pop
    JOIN
    cte_slateids slate
    on (pop.ID_NUM=slate.ID_NUM)
    JOIN
    cte_crs crs
    on (pop.ID_NUM=crs.ID_NUM and pop.DIV_CDE=crs.STUD_DIV)
    LEFT JOIN
    cte_fac fac
    on (crs.CRS_CDE=fac.CRS_CDE and crs.cw_sessyr=fac.TRM_CDE+fac.YR_CDE)
ORDER BY
    pop.ID_NUM,
    pop.DIV_CDE;

    set nocount off;
    REVERT
END

;
GO
