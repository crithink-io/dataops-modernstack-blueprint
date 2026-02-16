-- =============================================================================
-- Schema: APP_DB.RAW
-- Purpose: Landing zone for data synced by Fivetran (or other ELT tools).
--          Tables here are NOT managed by dbt — they are source tables.
-- =============================================================================

create or alter schema APP_DB.RAW
    data_retention_time_in_days = 7
    comment = 'Raw landing zone — Fivetran source tables';
