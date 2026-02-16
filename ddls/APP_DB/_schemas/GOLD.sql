-- =============================================================================
-- Schema: APP_DB.GOLD
-- Purpose: Zone 4 — Star schema (dimensions + facts) with business rules.
--          Tables managed by dbt.
-- =============================================================================

create or alter schema APP_DB.GOLD
    data_retention_time_in_days = 14
    comment = 'Zone 4 — Gold: star schema, dimensions and facts';
