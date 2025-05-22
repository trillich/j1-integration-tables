-- use mcintgr8;

-- =============================================
-- Author:		Will Trillich	
-- Create date: 05/21/2025
-- Description:	Inserts UHP records extracted from J1 into the INTGR_UHP holding table.
--
-- Modified:
-- =============================================
CREATE PROCEDURE [dbo].[PostUHP] 
    -- [TransactionID] [int] IDENTITY(1,1) NOT NULL,
	@SID                                varchar(9),
	@FIRST_NAME                         varchar(30) = NULL,
	@LAST_NAME                          varchar(60) = NULL,
	@DATE_OF_BIRTH                      varchar(24) = NULL, -- yyyy-mm-dd hh:mm:ss.fff
	@GENDER                             char(1)     = NULL,
	@ADDRESS_1                          varchar(60) = NULL,
	@ADDRESS_2                          varchar(60) = NULL,
	@CITY                               varchar(60) = NULL,
	@STATE                              char(2)     = NULL,
	@ZIP                                varchar(10) = NULL,
	@EMAIL                              varchar(40) = NULL,
	@INTERNATIONAL_STUDENT_INDICATOR    char(1)     = NULL,
	@TERM_CODE                          varchar(6)  = NULL,
	@ATHLETE                            char(1)     = NULL,
	@OUT_OF_STATE_INDICATOR             char(1)     = NULL,
	@ONLINE                             char(1)     = NULL

with execute as 'dbo'
AS
BEGIN
    set nocount on;

    set @DATE_OF_BIRTH = 
        case when @DATE_OF_BIRTH is not null
            -- then convert(varchar(24), convert(datetime, @DATE_OF_BIRTH), 121)
            then cast(cast(@DATE_OF_BIRTH as date) as varchar(10))
            else null
        end;

    insert into intgr_uhp (
        SID,
        FIRST_NAME,
        LAST_NAME,
        DATE_OF_BIRTH,
        GENDER,
        ADDRESS_1,
        ADDRESS_2,
        CITY,
        STATE,
        ZIP,
        EMAIL,
        INTERNATIONAL_STUDENT_INDICATOR,
        TERM_CODE,
        ATHLETE,
        OUT_OF_STATE_INDICATOR,
        ONLINE
    ) values (
        @SID,
        @FIRST_NAME,
        @LAST_NAME,
        @DATE_OF_BIRTH,
        @GENDER,
        @ADDRESS_1,
        @ADDRESS_2,
        @CITY,
        @STATE,
        @ZIP,
        @EMAIL,
        @INTERNATIONAL_STUDENT_INDICATOR,
        @TERM_CODE,
        @ATHLETE,
        @OUT_OF_STATE_INDICATOR,
        @ONLINE
    );

    revert;

end