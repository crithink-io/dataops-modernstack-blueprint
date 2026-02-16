-- =============================================================================
-- Table: APP_DB.RAW.PRODUCTS
-- Purpose: Raw products table synced by Fivetran. Source for dbt transient zone.
-- =============================================================================

create or alter table APP_DB.RAW.PRODUCTS (
    product_id      integer         not null,
    product_name    varchar(255),
    category        varchar(100),
    price           number(18, 2),
    created_at      timestamp_ntz,
    updated_at      timestamp_ntz
)
comment = 'Raw products — synced by Fivetran';
