{{
    config(
        materialized='incremental',
        unique_key='_reject_id',
        tags=['zone:silver', 'rejects']
    )
}}

with validated as (
    select * from {{ ref('slv_products_validated') }}
),

classified as (
    select
        product_id,
        product_name,
        category,
        brand,
        price,
        cost,
        _reject_reason,
        _silver_processed_at,
        current_timestamp() as _rejected_at,
        {{ dbt_utils.generate_surrogate_key(['product_id', 'product_name']) }} as _reject_id
    from validated
    where _is_business_valid = false
),

final as (
    select * from classified
    {% if is_incremental() %}
        where _silver_processed_at > (select max(_rejected_at) from {{ this }})
    {% endif %}
)

select * from final
