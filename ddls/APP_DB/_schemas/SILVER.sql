-- =============================================================================
-- Schema: APP_DB.SILVER
-- Purpose: Zone 3 — Cleaned, deduplicated, business-validated data.
--          Tables managed by dbt.
-- =============================================================================

create or alter schema APP_DB.SILVER
    data_retention_time_in_days = 14
    comment = 'Zone 3 — Silver: dedup, standardize, business validation';
