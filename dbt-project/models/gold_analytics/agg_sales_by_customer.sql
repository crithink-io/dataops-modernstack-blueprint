{{
    config(
        materialized='table',
        tags=['zone:gold_analytics']
    )
}}

-- Pre-aggregated customer sales metrics for Power BI consumption.

select
    dim.customer_id,
    dim.first_name,
    dim.last_name,
    dim.customer_tier,
    dim.city,
    dim.state_code,
    dim.country_code,
    dim.total_orders,
    dim.total_spent,
    dim.first_order_date,
    dim.last_order_date,
    datediff('day', dim.first_order_date, dim.last_order_date) as customer_lifetime_days,
    case
        when dim.total_orders > 0
        then dim.total_spent / dim.total_orders
        else 0
    end as avg_order_value
from {{ ref('dim_customers') }} as dim
