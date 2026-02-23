{{
    config(
        materialized='table',
        tags=['zone:gold']
    )
}}

with customers as (
    select * from {{ ref('slv_customers') }}
),

customer_metrics as (
    select
        customer_id,
        count(*) as total_orders,
        sum(total_amount) as total_spent,
        min(order_date) as first_order_date,
        max(order_date) as last_order_date
    from {{ ref('slv_orders') }}
    group by customer_id
),

final as (
    select
        cst.customer_id,
        cst.first_name,
        cst.last_name,
        cst.email,
        cst.phone,
        cst.address,
        cst.city,
        cst.state_code,
        cst.postal_code,
        cst.country_code,
        cst.created_at,
        cst.updated_at,
        coalesce(met.total_orders, 0) as total_orders,
        coalesce(met.total_spent, 0) as total_spent,
        met.first_order_date,
        met.last_order_date,
        case
            when met.total_spent >= 1000 then 'VIP'
            when met.total_spent >= 500  then 'Premium'
            when met.total_spent >= 100  then 'Regular'
            else 'New'
        end as customer_tier
    from customers as cst
    left join customer_metrics as met on cst.customer_id = met.customer_id
)

select * from final
