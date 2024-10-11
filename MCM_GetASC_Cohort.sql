SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[MCM_GetASC_Cohort]
@exec as bit = 1
WITH EXECUTE AS 'dbo'
AS
-- =============================================
-- Author:		Will Trillich (Serensoft)	
-- Create date: 10/9/2024
-- Description:	Generate ASC Cohort export
-- Modified:	
-- 
-- =============================================
BEGIN

       DECLARE @cterm varchar(6) = j1conv.dbo.MCM_FN_CALC_TRM('C');
       DECLARE @pterm varchar(6) =
              CASE 
                     WHEN @cterm LIKE '%WI' OR @cterm LIKE '%SP'
                     THEN j1conv.dbo.MCM_FN_CALC_TRM('PFA')
                     ELSE j1conv.dbo.MCM_FN_CALC_TRM('PSP')
              END;
       DECLARE @cyr int = cast(left(@cterm,4) as int);
       DECLARE @pyr int = cast(left(@pterm,4) as int);
       set @cterm=right(@cterm,2);
       set @pterm=right(@pterm,2);
    --    print @cterm+@pterm;

WITH
cte_pop as (
	--Just retrieve the unique population of ID's that match the previous, current and next academic years
	SELECT DISTINCT
            sm.ID_NUM
	 FROM
            STUDENT_MASTER sm WITH (nolock)
            JOIN
            DEGREE_HISTORY dh WITH (nolock)
                on sm.ID_NUM = dh.ID_NUM
	 WHERE sm.id_num in (
                SELECT distinct id_num
                FROM STUDENT_CRS_HIST sch
                WHERE stud_div IN ( 'UG', 'GR' )
                AND (
                    (sch.YR_CDE = @cyr and sch.TRM_CDE = @cterm)
                    OR
                    (sch.YR_CDE = @pyr and sch.TRM_CDE = @pterm)
                )
                AND sch.transaction_sts IN ( 'H', 'C', 'D' )
        )
            AND sm.CURRENT_CLASS_CDE NOT IN ( 'CE','NM','AV' )
            AND dh.MAJOR_1 <> 'GEN' -- omit nonmatric
            AND dh.cur_degree = 'Y'
)
-- select * from cte_pop order by id_num;
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
        and ai.IDENTIFIER_TYPE in ('SUG','SGPS')
        and (ai.BEGIN_DTE is null or ai.BEGIN_DTE <= getdate())
        and (ai.END_DTE is null or ai.END_DTE > getdate())
    GROUP BY ID_NUM
)
-- select * from cte_slateids order by id_num;
,
cte_attr_detail as (
    SELECT
        ID_NUM,
        ATTRIB_CDE
    FROM
        ATTRIBUTE_TRANS
    WHERE
        ID_NUM in (select id_num from cte_pop)
        and ATTRIB_END_DATE is null
        and ATTRIB_CDE in ('DEAN','PROM','COMP','HONR','AUST','PION','MACH')
)
-- select * from cte_attr_detail order by id_num desc
,
cte_attr as (
    SELECT
        ID_NUM,
        max(case when ATTRIB_CDE='DEAN' then ATTRIB_CDE else null end) DEAN,
        max(case when ATTRIB_CDE='PROM' then ATTRIB_CDE else null end) PROM,
        max(case when ATTRIB_CDE='COMP' then ATTRIB_CDE else null end) COMP,
        max(case when ATTRIB_CDE='HONR' then ATTRIB_CDE else null end) HONR,
        max(case when ATTRIB_CDE='AUST' then ATTRIB_CDE else null end) AUST,
        max(case when ATTRIB_CDE='PION' then ATTRIB_CDE else null end) PION,
        max(case when ATTRIB_CDE='MACH' then ATTRIB_CDE else null end) MACH
    FROM
        cte_attr_detail
    GROUP BY
        ID_NUM
)
-- select * from cte_attr order by id_num desc
,
cte_sport_detail
    AS (
        SELECT
            ID_NUM,
            SPORTS_CDE,
            YR_CDE,
            TRM_CDE,
            dense_rank() over (
                partition by id_num
                order by yr_cde,trm_cde desc
            ) x
        FROM SPORTS_TRACKING st
        WHERE
            st.ID_NUM in (select id_num from cte_pop)
            and
            (
                (st.YR_CDE = @cyr and st.TRM_CDE = @cterm)
                or
                (st.YR_CDE = @pyr and st.TRM_CDE = @pterm)
            )
        )
-- select * from cte_sport_detail order by id_num desc
,
cte_sport as (
    SELECT
        ID_NUM,
        max(case when x=1 then sports_cde else null end) sport1,
        max(case when x=2 then sports_cde else null end) sport2
    FROM
        cte_sport_detail
    GROUP BY
        ID_NUM
)
-- select * from cte_sport order by id_num desc
,
cte_emerg as (
    SELECT
        ID_NUM,
        concat(FIRST_NAME,LAST_NAME)    emerg_name,
        MOBILE_PHONE_NUM                emerg_num
    FROM
        EMERG_CONTACT_MAST
    WHERE
        ID_NUM in ( SELECT id_num FROM cte_pop )
        AND
        EMER_CON_SEQ = 1 -- FIXME maybe, no data to be sure =1 is canonical
)
,
cte_back2mack as (
    SELECT
        ID_NUM,
        MAX(STU_HANDBOOK)   stu_handbook,
        MAX(HANDBOOK)       handbook
    FROM
        MCM_BACK_TO_MACK
    WHERE
        ID_NUM in (SELECT id_num FROM cte_pop)
    GROUP BY
        ID_NUM
)
,
cte_veh as (
    SELECT
        id_num_veh_ownr id_num,
        vp_num
    FROM
        cm_sa_vehcl_reg veh
    WHERE
        id_num_veh_ownr in ( SELECT id_num FROM cte_pop )
)

SELECT
    slate.SUG               slate_undg_id,
    slate.SGPS              slate_gps_id,
    pop.ID_NUM              cx_id,
    attr.DEAN               dean,
    attr.PROM               promise,
    attr.COMP               compass,
    'FIXME'                 phoenix,
    attr.HONR               honors,
    attr.AUST               austin,
    attr.PION               pioneers,
    attr.MACH               mach,
    'FIXME'                 obrien,
    'FIXME'                 cathedral,
    'FIXME'                 augustine,
    sport.sport1,
    sport.sport2,
    nm.is_ferpa_protected   ferpa,
    emerg.emerg_name        emergency_contact_name,
    emerg.emerg_num         emergency_contact_number,
    'FIXME'                 parking_pass, -- CM_SA_VEHCL_REG.VP_NUM
    'FIXME'                 completed_yn, -- back2mack
    'FIXME'                 submitted_date,
    'FIXME'                 reason,
    'FIXME'                 return_to_campus_handbook,
    'FIXME'                 student_handbook
FROM
    cte_pop pop
    LEFT JOIN
    cte_attr attr
        on pop.ID_NUM = attr.ID_NUM
    LEFT JOIN
    cte_slateids slate
        on pop.ID_NUM = slate.ID_NUM
    LEFT JOIN
    cte_sport sport
        on pop.ID_NUM = sport.ID_NUM
    LEFT JOIN
    cte_emerg emerg
        on pop.ID_NUM = emerg.ID_NUM
    LEFT JOIN
    cte_back2mack b2m
        on pop.ID_NUM = b2m.ID_NUM

;

    set nocount off;
    REVERT
END

;
GO