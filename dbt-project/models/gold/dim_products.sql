{{
    config(
        materialized='table',
        tags=['zone:gold']
    )
}}

with products as (
    select * from {{ ref('slv_products') }}
),

product_metrics as (
    select
        product_id,
        count(*) as total_orders,
        sum(quantity) as total_quantity_sold,
        sum(total_price) as total_revenue,
        avg(unit_price) as avg_selling_price
    from {{ ref('slv_order_items') }}
    group by product_id
),

final as (
    select
        prd.product_id,
        prd.product_name,
        prd.category,
        prd.subcategory,
        prd.brand,
        prd.price,
        prd.cost,
        prd.description,
        prd.is_active,
        prd.created_at,
        prd.updated_at,
        coalesce(met.total_orders, 0)        as total_orders,
        coalesce(met.total_quantity_sold, 0) as total_quantity_sold,
        coalesce(met.total_revenue, 0)       as total_revenue,
        coalesce(met.avg_selling_price, 0)   as avg_selling_price,
        (prd.price - prd.cost)               as profit_margin,
        case
            when met.total_revenue >= 10000 then 'High Performance'
            when met.total_revenue >= 5000  then 'Medium Performance'
            when met.total_revenue >= 1000  then 'Low Performance'
            else 'No Sales'
        end as performance_category
    from products as prd
    left join product_metrics as met on prd.product_id = met.product_id
)

select * from final
