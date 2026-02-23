{{
    config(
        materialized='table',
        tags=['zone:silver']
    )
}}

with validated as (
    select * from {{ ref('slv_orders_validated') }}
),

final as (
    select
        order_id,
        customer_id,
        order_date,
        status,
        total_amount,
        shipping_address,
        billing_address,
        payment_method,
        created_at,
        updated_at,
        _source_system,
        _domain,
        _sensitivity_tag,
        _silver_processed_at
    from validated
    where _is_business_valid = true
)

select * from final
