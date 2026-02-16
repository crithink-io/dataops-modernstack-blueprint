{{
    config(
        materialized='incremental',
        unique_key='_reject_id',
        tags=['zone:silver', 'rejects']
    )
}}

select
    order_item_id,
    order_id,
    product_id,
    quantity,
    unit_price,
    total_price,
    _reject_reason,
    current_timestamp() as _rejected_at,
    {{ dbt_utils.generate_surrogate_key(['order_item_id', 'order_id']) }} as _reject_id
from {{ ref('slv_order_items_validated') }}
where _is_business_valid = false
{% if is_incremental() %}
    and _silver_processed_at > (select max(_rejected_at) from {{ this }})
{% endif %}
