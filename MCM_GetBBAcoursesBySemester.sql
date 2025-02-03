SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[MCM_GetBBAcoursesBySemester](
        @trm_cde varchar(2), -- 'FA';
        @yr_cde varchar(4), -- '2023';
        @sbtrm_cde varchar(2) -- 'F2';
)

WITH EXECUTE AS 'dbo'
AS
-- =============================================
-- Author:		Will Trillich (Serensoft)	
-- Create date: 1/28/2025
-- Description:	Generate BBA Bookstore COURSES filenames for 3 semesters
-- Modified:	

-- =============================================
BEGIN

    -- declare @trm_cde varchar(2) = 'FA';
    -- declare @yr_cde varchar(4) = '2023';
    -- declare @sbtrm_cde varchar(2) = 'F2';

    -- expected CSV header is:
    -- "Dept Code","Dept Name","Course Code","Course Name","Section Code","Instructor First Name","Instructor Last Name","Instructor/Course Contact Email","Max Enrollment","Current Enrollment"

    select
        -- sm.yr_cde,
        -- sm.trm_cde,
        -- sm.subterm_cde,
        trim(left(sm.crs_cde,5))                    dept_code,
        coalesce(c1.CRS_COMP_1_DESC,'[unknown]')    dept_name,
        sm.CRS_CDE                                  course_code,
        sm.CRS_TITLE                                course_name,
        trim(right(rtrim(sm.CRS_CDE),2))            section_code,
        nm.FIRST_NAME                               instructor_fname,
        nm.LAST_NAME                                instructor_lname,
        email.AlternateContact                      instructor_email,
        sm.CRS_CAPACITY                             max_enrollment,
        sm.CRS_ENROLLMENT                           current_enrollment
    from
        section_master sm
        LEFT JOIN
        CRS_COMP_1 c1
            on (left(sm.CRS_CDE,5) = c1.CRS_COMP_1)
        LEFT JOIN
        NameMaster nm
            on (sm.LEAD_INSTRUCTR_ID = nm.ID_NUM)
        LEFT JOIN
        AlternateContactMethod email
            on (sm.LEAD_INSTRUCTR_ID = email.ID_NUM
                and
                email.ADDR_CDE = '*EML'
                and
                email.IsActive = 1
            )
    where
        sm.yr_cde = @yr_cde
        AND
        sm.trm_cde = @trm_cde
        AND
        (
            sm.subterm_cde = @sbtrm_cde
            OR
            (sm.subterm_cde is null and @sbtrm_cde is null)
        )
    ORDER BY
        sm.CRS_CDE;


    set nocount off;
    REVERT
END

;
GO

-- testing:
exec MCM_GetBBAcoursesBySemester 'SP','2023','R1';
exec MCM_GetBBAcoursesBySemester 'FA','2024','F3';
