-- =============================================================================
-- Database: APP_DB
-- Purpose:  Main application database for the dbt pipeline.
--           Contains all zone schemas (transient, bronze, silver, gold, etc.)
-- =============================================================================

create or alter database APP_DB
    data_retention_time_in_days = 14
    comment = 'Application database for dbt medallion pipeline';
