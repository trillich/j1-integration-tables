-- =============================================
-- Author:		Will Trillich	
-- Create date: 05/20/2025
-- Description:	Purges the INTGR_UHPtable in prep for the next run
-- Modified:
-- =============================================
CREATE PROCEDURE [dbo].[Purge_UHP] 
	-- Add the parameters for the stored procedure here

WITH EXECUTE AS 'dbo'
AS
BEGIN
	SET NOCOUNT ON;
	
	TRUNCATE TABLE INTGR_UHP;

REVERT

END