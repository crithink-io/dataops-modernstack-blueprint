{{
    config(
        materialized='incremental',
        unique_key='_reject_id',
        tags=['zone:silver', 'rejects']
    )
}}

select
    order_id,
    customer_id,
    order_date,
    status,
    total_amount,
    _reject_reason,
    current_timestamp() as _rejected_at,
    {{ dbt_utils.generate_surrogate_key(['order_id', 'customer_id']) }} as _reject_id
from {{ ref('slv_orders_validated') }}
where _is_business_valid = false
{% if is_incremental() %}
    and _silver_processed_at > (select max(_rejected_at) from {{ this }})
{% endif %}
