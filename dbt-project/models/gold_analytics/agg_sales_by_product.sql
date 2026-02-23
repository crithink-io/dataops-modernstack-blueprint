{{
    config(
        materialized='table',
        tags=['zone:gold_analytics']
    )
}}

-- Pre-aggregated product sales metrics for Power BI consumption.

with source as (
    select * from {{ ref('dim_products') }}
),

final as (
    select
        product_id,
        product_name,
        category,
        subcategory,
        brand,
        price,
        cost,
        profit_margin,
        performance_category,
        total_orders,
        total_quantity_sold,
        total_revenue,
        avg_selling_price,
        case
            when total_revenue > 0
            then (total_revenue - (cost * total_quantity_sold)) / total_revenue
            else 0
        end as gross_margin_pct
    from source
)

select * from final
