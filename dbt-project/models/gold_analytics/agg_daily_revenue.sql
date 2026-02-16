{{
    config(
        materialized='table',
        tags=['zone:gold_analytics']
    )
}}

-- Daily revenue aggregation for Power BI dashboards.

select
    fct.order_date,
    count(distinct fct.order_id) as total_orders,
    count(distinct fct.customer_id) as unique_customers,
    sum(fct.total_price) as total_revenue,
    sum(fct.quantity) as total_units_sold,
    sum(fct.discount_amount) as total_discounts,
    avg(fct.unit_price) as avg_unit_price
from {{ ref('fct_orders') }} as fct
group by fct.order_date
