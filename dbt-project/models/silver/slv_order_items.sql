{{
    config(
        materialized='table',
        tags=['zone:silver']
    )
}}

with validated as (
    select * from {{ ref('slv_order_items_validated') }}
),

final as (
    select
        order_item_id,
        order_id,
        product_id,
        quantity,
        unit_price,
        total_price,
        discount_amount,
        created_at,
        _source_system,
        _domain,
        _sensitivity_tag,
        _silver_processed_at
    from validated
    where _is_business_valid = true
)

select * from final
