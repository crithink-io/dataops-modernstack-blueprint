-- =============================================================================
-- Database: _DB_UTILS
-- Purpose:  Common utilities database for CI/CD infrastructure.
--           Hosts PR-isolated schemas, stored procedures, and metadata.
-- =============================================================================

create or alter database _DB_UTILS
    data_retention_time_in_days = 1
    comment = 'CI/CD utilities — PR schemas, stored procedures, metadata';
