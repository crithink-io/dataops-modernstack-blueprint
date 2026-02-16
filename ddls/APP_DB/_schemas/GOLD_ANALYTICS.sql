-- =============================================================================
-- Schema: APP_DB.GOLD_ANALYTICS
-- Purpose: Zone 5 — Pre-aggregated BI-ready models.
--          Tables managed by dbt.
-- =============================================================================

create or alter schema APP_DB.GOLD_ANALYTICS
    data_retention_time_in_days = 14
    comment = 'Zone 5 — Gold Analytics: pre-aggregated BI-ready models';
