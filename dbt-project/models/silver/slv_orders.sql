{{
    config(
        materialized='table',
        tags=['zone:silver']
    )
}}

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
from {{ ref('slv_orders_validated') }}
where _is_business_valid = true
