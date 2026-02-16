{{
    config(
        materialized='table',
        tags=['zone:silver']
    )
}}

select
    product_id,
    product_name,
    description,
    category,
    subcategory,
    brand,
    price,
    cost,
    created_at,
    updated_at,
    _source_system,
    _domain,
    _sensitivity_tag,
    _silver_processed_at
from {{ ref('slv_products_validated') }}
where _is_business_valid = true
