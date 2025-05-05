SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[MCM_GetXfinity]
    @exec as int = 1
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

        declare @cterm as varchar(6) = dbo.MCM_FN_CALC_TRM('C'); -- "current term YYYYss"
        set @cterm = substring(@cterm,5,2) + substring(@cterm,1,4); -- "ssYYYY"

WITH
cte_dorm
    as (
        SELECT
            ra.id_num,
            ra.room_assign_sts, -- FIXME: a=assigned? vs u=unassigned?
            ra.bldg_cde,
            ra.room_cde
        FROM
            ROOM_ASSIGN ra with (nolock)
        WHERE
            sess_cde = @cterm
            /*
            NOTE:
            cx script for xfinity also deliberately
            omitted "Royal Crest" and "TBA"
            */
    )
    ,
/*

NOTE:

cx script for xfinity had two additional mechanisms to include students
into the population, aside from dorm status:
    - involve_rec.invl = INVOLVEMENT
    - ctc_rec.resrc = XFINITY
        We'd often offer ctc_rec as a handy way for offices to have a bit of manual control

*/
cte_emails
    as (
        select
            eml.ID_NUM,
            AlternateContact email,
            SUBSTRING(AlternateContact, 1, CHARINDEX('@', AlternateContact)-1) AS username
        from
            AlternateContactMethod eml with (nolock)
        WHERE
            eml.ADDR_CDE in ('*EML')
            and
            AlternateContact like '%@merrimack.edu'
            -- and
            -- id_num in (select id_num from cte_dorm with (nolock))
    )

-- two piffly ol columns:
SELECT 
    eml.username                        username,
    case
        when dorm.room_assign_sts = 'A'
        then 'TRUE'
        else 'FALSE'
    end as                              xocentitlement
FROM
    cte_emails eml with (nolock)
    INNER JOIN
    cte_dorm dorm with (nolock)
        ON eml.id_num = dorm.id_num
;

    set nocount off;
    REVERT
END

;
GO

