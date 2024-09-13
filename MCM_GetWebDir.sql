SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[MCM_GetWebDir]
@exec as bit = 1

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
            u.ID_NUM            id_number,
            'FIXME' ext,
            n.LAST_NAME,
            n.FIRST_NAME,
            u.EMP_TITLE         personnel_title,
            -- u.EMP_HOME_DEPT,
            'FIXME' department_long_text,
            -- u.EMP_BUILD,
            b.BUILDING_DESC     building_text,
            u.EMP_OFFICE        office,
            'FIXME'             mail,
            acm.alternatecontact alternate_address_line_1,
            'FIXME'             personal_designation
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
    order by LAST_NAME,FIRST_NAME,ID_NUMBER;

    set nocount off;
    REVERT
END

;
GO
