SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/* if MERGE is bad juju maybe we should use the pattern here
https://stackoverflow.com/questions/108403/solutions-for-insert-or-update-on-sql-server/21209295#21209295

    BEGIN TRANSACTION;

    UPDATE dbo.table WITH (UPDLOCK, SERIALIZABLE) 
    SET ... WHERE PK = @PK;

    IF @@ROWCOUNT = 0
    BEGIN
    INSERT dbo.table(PK, ...) SELECT @PK, ...;
    END

    COMMIT TRANSACTION;

More discussion:
https://michaeljswart.com/2017/07/sql-server-upsert-patterns-and-antipatterns/

    SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
    BEGIN TRAN

    UPDATE dbo.AccountDetails
    SET Etc = @Etc
    WHERE Email = @Email

    INSERT dbo.AccountDetails ( Email, Etc )
    SELECT @Email, @Etc
    WHERE @@ROWCOUNT=0

    COMMIT

For grab-serial-id whether on update or insert:
https://stackoverflow.com/questions/16838724/using-output-to-set-a-variable-in-a-merge-statement
https://stackoverflow.com/a/16838803/9627909

*/

ALTER PROCEDURE MCM_PostBBAbooks
    -- derive YR/TERM from incoming CSV FILE NAME
    @yr int,
    @term nvarchar(2),
    -- the rest come from the CSV data
    @Department     NVARCHAR(100),
    @Course         NVARCHAR(100),
    @Section        NVARCHAR(100),
    @Instructor     NVARCHAR(100),
    @Capacity       INT,
    @EstEnrollment  INT,
    @Enrollment     INT,
    @Required       NVARCHAR(10),
    @ISBN           NVARCHAR(20),
    @Title          NVARCHAR(200),
    @Author         NVARCHAR(200),
    @SaleNew        DECIMAL(10, 2),
    @SaleUsed       DECIMAL(10, 2),
    @RentNew        DECIMAL(10, 2),
    @RentUsed       DECIMAL(10, 2),
    @UsedOnHand     INT,
    @NewOnHand      INT

WITH EXECUTE AS 'dbo'
AS
BEGIN
    SET XACT_ABORT ON;
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL SERIALIZABLE; -- https://michaeljswart.com/2017/07/sql-server-upsert-patterns-and-antipatterns/

    IF @isbn='' or @title='' or @author=''
    BEGIN
        -- ain't got any real info, skip this empty-ish record
        return;
    END

    IF @title like '%NO TEXT%' or @author like '%NO TEXT%'
    BEGIN
        -- no book here, skip it
        return;
    END

    DECLARE
        @bookno     int           = 0,
        @secno      varchar(20)   = @course + ' ' + @section,
        @course_ok  int           = 0,

        @msg        varchar(5000) = '',
        @job        varchar(20)   = 'MCM_PostBBAbooks',
        @user       varchar(500)  = ORIGINAL_LOGIN(),
        @xct        int           = @@TRANCOUNT;
        -- transaction voodoo from https://rusanu.com/2009/06/11/exception-handling-and-nested-transactions/

    -- Make sure we have a valid course/section:
    SELECT @course_ok = count(*)
    FROM section_master
    WHERE TRM_CDE = @term AND YR_CDE = @yr AND CRS_CDE = @secno;

    if @course_ok <> 1
    BEGIN
        set @msg = @job + ': Yr/Term/Course not found in section_master: ' +
            cast(@yr as varchar) + '/' + @term + '/' + @secno;
        RAISERROR(@msg, 16, 1);
    END

    BEGIN TRY

        if @xct = 0
            -- we weren't already in a transaction, so start one
            BEGIN TRANSACTION;
        else
            -- we were already in a transaction, so save it
            SAVE TRANSACTION @job;

        ------------------------------
        -- Handle TEXTBOOK_DEF record:
        ------------------------------
        MERGE INTO textbook_def AS tgt
        USING (
            SELECT
                @isbn   AS isbn,
                @author AS authors,
                @title  AS book_title
            ) AS src
        ON (tgt.isbn_cde = src.isbn OR tgt.isbn_13 = src.isbn)
        WHEN MATCHED THEN
            UPDATE
            SET @bookno        = tgt.book_seq_num, -- <== tricky tricky CHEATING :)
                tgt.authors    = src.authors,
                tgt.book_title = src.book_title,
                tgt.user_name  = @user,
                tgt.job_name   = @job,
                tgt.job_time   = getdate()
        WHEN NOT MATCHED THEN
            INSERT (isbn_cde, isbn_13, authors, book_title, user_name, job_name, job_time)
            VALUES (src.isbn, src.isbn, src.authors, src.book_title, @user, @job, getdate())
            -- according to https://www.sqlservercentral.com/articles/the-output-clause-for-the-merge-statements
            -- this should work for UPDATE and for INSERT
        -- OUTPUT inserted.book_seq_num INTO @bookno # nope, need table-var not int-var
        ;
        SET @bookno = ISNULL(@bookno,SCOPE_IDENTITY());

        if not(@bookno > 0)
        BEGIN
            SET @msg = @job + ': Still no book_seq_num? ' +
                cast(@yr as varchar) + '/' + @term + '/' + @secno + '/' + @title;
            RAISERROR(@msg, 16, 1);
        END

        --------------------------------
        -- handle TEXTBOOK_TABLE record:
        --------------------------------

        -- Make sure we've got one to link yr/term/crs to book
        MERGE textbook_table tgt
        USING (
                SELECT
                    @bookno AS book_seq_num,
                    @yr     AS yr_cde,
                    @term   AS trm_cde,
                    @secno  AS crs_cde
        ) src
        ON tgt.book_seq_num = src.book_seq_num
            AND tgt.yr_cde  = src.yr_cde
            AND tgt.trm_cde = src.trm_cde
            AND tgt.crs_cde = src.crs_cde
        WHEN NOT MATCHED THEN
            INSERT ( yr_cde, trm_cde, crs_cde, book_seq_num, user_name, job_name, job_time)
            VALUES ( src.yr_cde, src.trm_cde, src.crs_cde, src.book_seq_num, @user, @job, getdate())
        -- WHEN NOT MATCHED BY SOURCE
        --  DELETE
        ;

        --------------------------------------
        -- handle TEXTBOOK_COST_PRICE records:
        --------------------------------------

        -- NEW BOOK FOR SALE
        if @SaleNew > 0.0
        BEGIN
            MERGE textbook_cost_price as tgt
            USING (
                SELECT
                    @bookno  AS book_seq_num,
                    'JN'     AS cost_price_type,
                    @SaleNew AS price
                    ) as src
            ON tgt.book_seq_num=src.book_seq_num
                AND tgt.cost_price_type = src.cost_price_type
            WHEN NOT MATCHED THEN
                -- sale item not found, so add it:
                INSERT (book_seq_num,cost_price_type,price,user_name,job_name,job_time)
                VALUES(src.book_seq_num,src.cost_price_type,src.price,@user,@job,getdate())
            WHEN MATCHED THEN
                -- sale item FOUND, just make sure it's current:
                UPDATE SET
                    tgt.price     = src.price,
                    tgt.user_name = @user,
                    tgt.job_name  = @job,
                    tgt.job_time  = getdate()
            ;
        END
        ELSE
        BEGIN
            -- price NULL or <0.0 so we ain't got none to sell
            DELETE FROM textbook_cost_price
            WHERE book_seq_num = @bookno
              AND cost_price_type = 'JN'
        END

        -- Used book for sale:
        if @SaleUsed > 0.0
        BEGIN
            MERGE textbook_cost_price as tgt
            USING (
                SELECT
                    @bookno   AS book_seq_num,
                    'JU'      AS cost_price_type,
                    @SaleUsed AS price
                    ) as src
            ON tgt.book_seq_num=src.book_seq_num
                AND tgt.cost_price_type = src.cost_price_type
            WHEN NOT MATCHED THEN
                -- sale item not found, so add it:
                INSERT (book_seq_num,cost_price_type,price,user_name,job_name,job_time)
                VALUES(src.book_seq_num,src.cost_price_type,src.price,@user,@job,getdate())
            WHEN MATCHED THEN
                -- sale item FOUND, just make sure it's current:
                UPDATE SET
                    tgt.price     = src.price,
                    tgt.user_name = @user,
                    tgt.job_name  = @job,
                    tgt.job_time  = getdate()
            ;
        END
        ELSE
        BEGIN
            -- price NULL or <0.0 so we ain't got none to sell
            DELETE FROM textbook_cost_price
            WHERE book_seq_num = @bookno
              AND cost_price_type = 'JU'
        END

        -- Used book for rent:
        if @RentUsed > 0.0
        BEGIN
            MERGE textbook_cost_price as tgt
            USING (
                SELECT
                    @bookno   AS book_seq_num,
                    'JR'      AS cost_price_type,
                    @RentUsed AS price
                    ) as src
            ON tgt.book_seq_num=src.book_seq_num
                AND tgt.cost_price_type = src.cost_price_type
            WHEN NOT MATCHED THEN
                -- sale item not found, so add it:
                INSERT (book_seq_num,cost_price_type,price,user_name,job_name,job_time)
                VALUES(src.book_seq_num,src.cost_price_type,src.price,@user,@job,getdate())
            WHEN MATCHED THEN
                -- sale item FOUND, just make sure it's current:
                UPDATE SET
                    tgt.price     = src.price,
                    tgt.user_name = @user,
                    tgt.job_name  = @job,
                    tgt.job_time  = getdate()
            ;
        END
        ELSE
        BEGIN
            -- price NULL or <0.0 so we ain't got none to rent
            DELETE FROM textbook_cost_price
            WHERE book_seq_num = @bookno
              AND cost_price_type = 'JR'
        END

        if @xct = 0
            -- we weren't already in a transaction, we made our own:
            COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000);
        DECLARE @ErrorSeverity INT;
        DECLARE @ErrorState INT;
        DECLARE @XState INT;
        SELECT
            @ErrorMessage   = ERROR_MESSAGE(),
            @ErrorSeverity  = ERROR_SEVERITY(),
            @ErrorState     = ERROR_STATE(),
            @XState         = XACT_STATE();

		IF @XState = -1
			ROLLBACK TRANSACTION;
		IF @XState = 1 and @xct = 0
            ROLLBACK TRANSACTION;
        IF @XState = 1 and @xct > 0
			ROLLBACK TRANSACTION @job;

		SET @msg = 'SP ' + @job + ' Error(' + Cast(Error_Number() AS varchar(10)) + '): ' + Error_Message();

		-- exec MCM_Error_Handler @msg, @id_num, @job;
		RAISERROR(N'%s', @errorseverity, @errorstate, @msg);

    END CATCH

END;
