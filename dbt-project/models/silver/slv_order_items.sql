{{
    config(
        materialized='table',
        tags=['zone:silver']
    )
}}

select
    order_item_id,
    order_id,
    product_id,
    quantity,
    unit_price,
    total_price,
    created_at,
    updated_at,
    _source_system,
    _domain,
    _sensitivity_tag,
    _silver_processed_at
from {{ ref('slv_order_items_validated') }}
where _is_business_valid = true
