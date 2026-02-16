-- Singular test: assert fact grain (one row per order_item_id).
-- Use this pattern for any fact table to ensure no duplicate grain.
select
    order_item_id,
    count(*) as row_count
from {{ ref('fct_orders') }}
group by order_item_id
having count(*) > 1
