{{
    config(
        materialized='table',
        tags=['zone:silver']
    )
}}

select
    customer_id,
    first_name,
    last_name,
    email,
    phone,
    address,
    city,
    state_code,
    postal_code,
    country_code,
    created_at,
    updated_at,
    _source_system,
    _domain,
    _sensitivity_tag,
    _silver_processed_at
from {{ ref('slv_customers_validated') }}
where _is_business_valid = true
