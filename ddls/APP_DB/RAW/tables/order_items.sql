-- =============================================================================
-- Table: APP_DB.RAW.ORDER_ITEMS
-- Purpose: Raw order items table synced by Fivetran. Source for dbt transient zone.
-- =============================================================================

create or alter table APP_DB.RAW.ORDER_ITEMS (
    order_item_id   integer         not null,
    order_id        integer         not null,
    product_id      integer         not null,
    quantity        integer,
    unit_price      number(18, 2),
    discount_amount number(18, 2),
    created_at      timestamp_ntz,
    updated_at      timestamp_ntz
)
comment = 'Raw order items — synced by Fivetran';
