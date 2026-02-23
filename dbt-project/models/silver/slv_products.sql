{{
    config(
        materialized='table',
        tags=['zone:silver']
    )
}}

with validated as (
    select * from {{ ref('slv_products_validated') }}
),

final as (
    select
        product_id,
        product_name,
        description,
        category,
        subcategory,
        brand,
        price,
        cost,
        is_active,
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
