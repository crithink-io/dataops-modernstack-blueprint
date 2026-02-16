-- =============================================================================
-- Schema: APP_DB.TRANSIENT
-- Purpose: Zone 1 — Truncate & reload landing. Technical validation.
--          Tables managed by dbt (dbt creates/replaces them each run).
-- =============================================================================

create or alter schema APP_DB.TRANSIENT
    data_retention_time_in_days = 1
    comment = 'Zone 1 — Transient: truncate & reload, technical validation';
