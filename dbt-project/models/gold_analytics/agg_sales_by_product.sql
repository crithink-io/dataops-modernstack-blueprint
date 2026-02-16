{{
    config(
        materialized='table',
        tags=['zone:gold_analytics']
    )
}}

-- Pre-aggregated product sales metrics for Power BI consumption.

select
    dim.product_id,
    dim.product_name,
    dim.category,
    dim.subcategory,
    dim.brand,
    dim.price,
    dim.cost,
    dim.profit_margin,
    dim.performance_category,
    dim.total_orders,
    dim.total_quantity_sold,
    dim.total_revenue,
    dim.avg_selling_price,
    case
        when dim.total_revenue > 0
        then (dim.total_revenue - (dim.cost * dim.total_quantity_sold)) / dim.total_revenue
        else 0
    end as gross_margin_pct
from {{ ref('dim_products') }} as dim
