SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[MCM_GetASC_stuAcadDaily]
    @exec as bit = 1
WITH EXECUTE AS 'dbo'
AS
-- =============================================
-- Author:		Will Trillich (Serensoft)	
-- Create date: 10/15/2024
-- Description:	Generate ASC stu-acad export for slate
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
                AND sch.YR_CDE in (@curyr)
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
cte_reg_seq as (
    SELECT
        ID_NUM,
        YR_CDE,
        TRM_CDE,
        MIN(SEQ_NUM) seq -- or maybe this should be MAX for reg_clearance? FIXME
    FROM
        REG_CLEARANCE
    WHERE
        ID_NUM in ( SELECT ID_NUM FROM cte_pop )
        and
        YR_CDE = @curyr
        -- and
        -- TRM_CDE = @cterm
    GROUP BY
        ID_NUM,
        YR_CDE,
        TRM_CDE
),
cte_reg_detail as (
    SELECT
        seq.ID_NUM,
        reg.[USER_NAME],
        reg.JOB_TIME,
        reg.YR_CDE,
        reg.TRM_CDE
    FROM
        REG_CLEARANCE reg
        JOIN
        cte_reg_seq seq
            on reg.ID_NUM = seq.ID_NUM 
            and reg.YR_CDE = seq.YR_CDE 
            and reg.TRM_CDE = seq.TRM_CDE 
            and reg.SEQ_NUM = seq.seq -- if there's more than one seq, we just want the 'priority' one per semester
)
,
cte_reg as (
    SELECT
        ID_NUM,
        max(case when TRM_CDE='FA' then [USER_NAME] else null end     ) fa_regclr_by,
        max(case when TRM_CDE='FA' then [JOB_TIME] else null end      ) fa_regclr_date,
        max(case when TRM_CDE='FA' then [TRM_CDE]+@curyr else null end) fa_regclr,
        max(case when TRM_CDE='SP' then [USER_NAME] else null end     ) sp_regclr_by,
        max(case when TRM_CDE='SP' then [JOB_TIME] else null end      ) sp_regclr_date,
        max(case when TRM_CDE='SP' then [TRM_CDE]+@curyr else null end) sp_regclr
    FROM
        cte_reg_detail
    GROUP BY
        ID_NUM
)
,
cte_terms_detail as (
    SELECT
    -- top 1000
        ID_NUM,
        TRM_CDE,
        DIV_CDE + TRM_CDE       semyr,
        LOCAL_HRS_GPA           gpa,
        TRM_HRS_ATTEMPT         attempted,
        TRM_HRS_ATTEMPT         reg_hrs,
        TRM_HRS_EARNED          earned
    FROM
        STUD_TERM_SUM_DIV
    -- order by id_num desc
    WHERE
        ID_NUM in ( select ID_NUM from cte_pop )
        AND
        YR_CDE = @curyr
)
,
cte_terms as (
    SELECT
        ID_NUM,
        MAX(case when TRM_CDE='FA' then semyr else null end) fa_stuacad_semyr,
        MAX(case when TRM_CDE='FA' then gpa else null end  ) fa_stuacad_gpa,
        MAX(case when TRM_CDE='FA' then attempted else null end) fa_stuacad_att_hrs,
        MAX(case when TRM_CDE='FA' then reg_hrs else null end) fa_stuacad_reg_hrs,
        MAX(case when TRM_CDE='FA' then earned else null end   ) fa_stuacad_earn_hrs,
        MAX(case when TRM_CDE='SP' then semyr else null end) sp_stuacad_semyr,
        MAX(case when TRM_CDE='SP' then gpa else null end  ) sp_stuacad_gpa,
        MAX(case when TRM_CDE='SP' then attempted else null end) sp_stuacad_att_hrs,
        MAX(case when TRM_CDE='SP' then reg_hrs else null end) sp_stuacad_reg_hrs,
        MAX(case when TRM_CDE='SP' then earned else null end   ) sp_stuacad_earn_hrs,
        MAX(case when TRM_CDE='SU' then semyr else null end) su_stuacad_semyr,
        MAX(case when TRM_CDE='SU' then gpa else null end  ) su_stuacad_gpa,
        MAX(case when TRM_CDE='SU' then attempted else null end) su_stuacad_att_hrs,
        MAX(case when TRM_CDE='SU' then reg_hrs else null end) su_stuacad_reg_hrs,
        MAX(case when TRM_CDE='SU' then earned else null end   ) su_stuacad_earn_hrs,
        MAX(case when TRM_CDE='WI' then semyr else null end) wi_stuacad_semyr,
        MAX(case when TRM_CDE='WI' then gpa else null end  ) wi_stuacad_gpa,
        MAX(case when TRM_CDE='WI' then attempted else null end) wi_stuacad_att_hrs,
        MAX(case when TRM_CDE='WI' then reg_hrs else null end) wi_stuacad_reg_hrs,
        MAX(case when TRM_CDE='WI' then earned else null end   ) wi_stuacad_earn_hrs
    FROM
        cte_terms_detail
    GROUP BY
        ID_NUM
)

SELECT
    slate.SUG                       slate_id,
    slate.SGPS                      slate_guid_asc,
    pop.ID_NUM                      cx_id,
    pop.DIV_CDE                     prog_code,

    reg.fa_regclr,
    reg.fa_regclr_by,
    reg.fa_regclr_date,

    reg.sp_regclr,
    reg.sp_regclr_by,
    reg.sp_regclr_date,

    terms.fa_stuacad_att_hrs,
    terms.fa_stuacad_earn_hrs,
    terms.fa_stuacad_gpa,
    terms.fa_stuacad_reg_hrs,
    terms.fa_stuacad_semyr,

    terms.sp_stuacad_att_hrs,
    terms.sp_stuacad_earn_hrs,
    terms.sp_stuacad_gpa,
    terms.sp_stuacad_reg_hrs,
    terms.sp_stuacad_semyr,

    terms.su_stuacad_att_hrs,
    terms.su_stuacad_earn_hrs,
    terms.su_stuacad_gpa,
    terms.su_stuacad_reg_hrs,
    terms.su_stuacad_semyr,

    terms.wi_stuacad_att_hrs,
    terms.wi_stuacad_earn_hrs,
    terms.wi_stuacad_gpa,
    terms.wi_stuacad_reg_hrs,
    terms.wi_stuacad_semyr

FROM
    cte_pop pop
    LEFT JOIN
    cte_slateids slate
        on pop.ID_NUM = slate.ID_NUM
    LEFT JOIN
    cte_reg reg
        on pop.ID_NUM = reg.ID_NUM
    LEFT JOIN
    cte_terms terms
        on pop.ID_NUM = terms.ID_NUM
;

    set nocount off;
    REVERT
END

;
GO
