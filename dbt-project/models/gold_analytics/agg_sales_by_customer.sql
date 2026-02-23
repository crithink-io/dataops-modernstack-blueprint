{{
    config(
        materialized='table',
        tags=['zone:gold_analytics']
    )
}}

-- Pre-aggregated customer sales metrics for Power BI consumption.

with source as (
    select * from {{ ref('dim_customers') }}
),

final as (
    select
        customer_id,
        first_name,
        last_name,
        customer_tier,
        city,
        state_code,
        country_code,
        total_orders,
        total_spent,
        first_order_date,
        last_order_date,
        datediff('day', first_order_date, last_order_date) as customer_lifetime_days,
        case
            when total_orders > 0
            then total_spent / total_orders
            else 0
        end as avg_order_value
    from source
)

select * from final
