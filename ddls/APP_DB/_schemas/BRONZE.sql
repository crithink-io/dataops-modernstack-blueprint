-- =============================================================================
-- Schema: APP_DB.BRONZE
-- Purpose: Zone 2 — Append-only raw history with metadata tagging.
--          Tables managed by dbt (incremental materialization).
-- =============================================================================

create or alter schema APP_DB.BRONZE
    data_retention_time_in_days = 14
    comment = 'Zone 2 — Bronze: append-only raw history';
