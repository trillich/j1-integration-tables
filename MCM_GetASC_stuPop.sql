SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[MCM_GetASC_stuPop]
    @exec as bit = 1
WITH EXECUTE AS 'dbo'
AS
-- =============================================
-- Author:		Will Trillich (Serensoft)	
-- Create date: 10/3/2024
-- Description:	Generate ASC/connect populations into holding table _msm_asc_stu_pop
-- Modified:
-- ...this procedure sets up _msm_asc_stu_pop for other SP to use as a filter
-- =============================================
BEGIN
    set nocount on;

    declare @cterm as VARCHAR(6) = '2024FA'; -- for debugging
    SET @cterm = dbo.MCM_FN_CALC_TRM('C');
    declare @curyr as INT        = cast(left(@cterm,4) as int);
    declare @nxtyr as INT        = @curyr + 1;

    SET @cterm = concat(right(@cterm,2),cast(@curyr as char(4)));

    IF NOT EXISTS (SELECT * FROM sys.tables WHERE object_id = OBJECT_ID(N'[dbo].[_mcm_asc_stu_pop]'))
        create table _mcm_asc_stu_pop (
            id_num integer,
            div char(2)
        );
    -- GO

    truncate table _mcm_asc_stu_pop; -- zzzzzzzzapit!

with
cte_stu as (
    select
        sm.ID_NUM,
        can.CUR_STAGE           stage, -- FIXME if this ain't right
        sm.CURRENT_CLASS_CDE    class,
        can.CUR_DIV             div,
        sm.ENTRANCE_TRM,
        sm.ENTRANCE_YR
    from
        STUDENT_MASTER sm with (nolock)
        JOIN
        CANDIDATE can with (nolock)
        ON (sm.ID_NUM = can.ID_NUM and sm.CUR_STUD_DIV = can.CUR_DIV)
        /*
        on CX we also used webuserid_table to make sure they had evolved to 
        at least have a real user_name (not just digits, something > 'A')...
        also id_rec.valid <> 'N'
        */
    WHERE
        sm.ENTRANCE_YR in ( @curyr, @nxtyr )
    )
-- select * from cte_stu;
,
cte_enrstat as (
    SELECT
        can.ID_NUM,
        can.DIV_CDE     div
    FROM
        CANDIDACY can with (nolock)
        JOIN
        cte_stu stu
        on (can.ID_NUM = stu.ID_NUM and can.DIV_CDE = stu.div and can.TRM_CDE = stu.ENTRANCE_TRM and can.YR_CDE = stu.ENTRANCE_YR)
    WHERE -- "confirmed" at any point in the past
        can.STAGE in ('DEPT','FIXME') -- in CX it was enrstat=CONFIRM|CONDPAID
)
-- select * from cte_enrstat
,
cte_cur as (
    SELECT
        sm.id_num,
        stu.div
    FROM
        STUDENT_MASTER sm with (nolock)
        join
        cte_stu stu with (nolock)
        on (sm.ID_NUM = stu.ID_NUM and sm.CUR_STUD_DIV = stu.div)
    WHERE -- "confirmed" currently
        stu.stage in ('DEPT','FIXME') -- in CX it was enrstat=CONFIRM|CONDPAID
)
-- select * from cte_cur
,
cte_pop as (
    SELECT * from cte_enrstat
    UNION
    SELECT * from cte_cur
)

insert
into _mcm_asc_stu_pop
select *
from cte_pop
;

select count(*) ct from _mcm_asc_stu_pop; -- return value, # of records

    set nocount off;
    REVERT
END

;
GO
