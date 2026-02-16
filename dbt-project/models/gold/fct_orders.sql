{{
    config(
        materialized='table',
        tags=['zone:gold']
    )
}}

-- Fact table: grain = one row per order_item_id.
-- Contains only foreign keys + measures. Join to dim_customers / dim_products for attributes.

with orders as (
    select * from {{ ref('slv_orders') }}
),

order_items as (
    select * from {{ ref('slv_order_items') }}
)

select
    itm.order_item_id,
    itm.order_id,
    ord.customer_id,
    itm.product_id,
    ord.order_date,
    ord.status,
    ord.payment_method,
    itm.quantity,
    itm.unit_price,
    itm.total_price,
    itm.discount_amount,
    ord.total_amount as order_total,
    itm.created_at
from order_items as itm
inner join orders as ord on itm.order_id = ord.order_id
