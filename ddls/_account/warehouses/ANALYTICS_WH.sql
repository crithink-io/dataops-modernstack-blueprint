-- =============================================================================
-- Warehouse: ANALYTICS_WH
-- Purpose:   Compute warehouse for dbt builds and BI queries.
-- =============================================================================

create or alter warehouse ANALYTICS_WH
    warehouse_size       = 'x-small'
    auto_suspend         = 60
    auto_resume          = true
    initially_suspended  = true
    comment              = 'Compute warehouse for dbt builds and analytics queries';
