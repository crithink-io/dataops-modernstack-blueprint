-- =============================================================================
-- Table: APP_DB.RAW.CUSTOMERS
-- Purpose: Raw customers table synced by Fivetran. Source for dbt transient zone.
-- =============================================================================

create or alter table APP_DB.RAW.CUSTOMERS (
    customer_id     integer         not null,
    first_name      varchar(100),
    last_name       varchar(100),
    email           varchar(255),
    created_at      timestamp_ntz,
    updated_at      timestamp_ntz
)
comment = 'Raw customers — synced by Fivetran';
