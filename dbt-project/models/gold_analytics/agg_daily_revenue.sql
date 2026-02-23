{{
    config(
        materialized='table',
        tags=['zone:gold_analytics']
    )
}}

-- Daily revenue aggregation for Power BI dashboards.

with source as (
    select * from {{ ref('fct_orders') }}
),

final as (
    select
        order_date,
        count(distinct order_id)   as total_orders,
        count(distinct customer_id) as unique_customers,
        sum(total_price)            as total_revenue,
        sum(quantity)               as total_units_sold,
        sum(discount_amount)        as total_discounts,
        avg(unit_price)             as avg_unit_price
    from source
    group by order_date
)

select * from final
