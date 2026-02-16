-- =============================================================================
-- Table: APP_DB.RAW.ORDERS
-- Purpose: Raw orders table synced by Fivetran. Source for dbt transient zone.
-- =============================================================================

create or alter table APP_DB.RAW.ORDERS (
    order_id        integer         not null,
    customer_id     integer         not null,
    order_date      date,
    status          varchar(50),
    payment_method  varchar(50),
    order_total     number(18, 2),
    created_at      timestamp_ntz,
    updated_at      timestamp_ntz
)
comment = 'Raw orders — synced by Fivetran';
