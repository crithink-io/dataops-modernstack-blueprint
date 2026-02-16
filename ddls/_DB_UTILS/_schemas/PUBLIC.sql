-- =============================================================================
-- Schema: _DB_UTILS.PUBLIC
-- Purpose: Default schema for shared utilities (stored procedures, metadata).
-- =============================================================================

create or alter schema _DB_UTILS.PUBLIC
    data_retention_time_in_days = 1
    comment = 'Shared utilities — stored procedures for CI/CD';
