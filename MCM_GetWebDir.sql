SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[MCM_GetWebDir]

WITH EXECUTE AS 'dbo'
AS
-- =============================================
-- Author:		Will Trillich (Serensoft)	
-- Create date: 9/10/2024
-- Description:	Generate Camput Directory data export
-- Modified:	
-- 
-- =============================================
BEGIN

    WITH
    cte_empl as (
        SELECT
            u.ID_NUM,
            'FIXME' ext,
            n.LAST_NAME,
            n.FIRST_NAME,
            u.EMP_TITLE,
            u.EMP_HOME_DEPT,
            'FIXME' department_long_text,
            -- u.EMP_BUILD,
            b.BUILDING_DESC,
            u.EMP_OFFICE,
            'FIXME' mail_stop,
            acm.alternatecontact email
        FROM
            NAME_MASTER_UDF u with (nolock)
            join
            NameMaster n with (nolock)
            on u.ID_NUM = n.ID_NUM
            left join
            alternatecontactmethod acm WITH (nolock)
            on u.ID_NUM = acm.ID_NUM
                AND acm.addr_cde = '*EML'
                AND acm.alternatecontact LIKE '%@merrimack.edu'
            left join
            BUILDING_MASTER b
            on u.EMP_BUILD = b.BLDG_CDE
        -- WHERE
        --     EMP_HIRE_DTE < getdate()
        --     and
        --     (EMP_TERM_DTE > getdate() or EMP_TERM_DTE is null)
    )
    select *
    from cte_empl
    order by LAST_NAME,FIRST_NAME,ID_NUM;

    set nocount off;
    REVERT
END

;
GO
