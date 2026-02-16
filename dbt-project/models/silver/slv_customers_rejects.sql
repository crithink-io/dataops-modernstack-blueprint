{{
    config(
        materialized='incremental',
        unique_key='_reject_id',
        tags=['zone:silver', 'rejects']
    )
}}

select
    customer_id,
    first_name,
    last_name,
    email,
    _reject_reason,
    current_timestamp() as _rejected_at,
    {{ dbt_utils.generate_surrogate_key(['customer_id', 'email']) }} as _reject_id
from {{ ref('slv_customers_validated') }}
where _is_business_valid = false
{% if is_incremental() %}
    and _silver_processed_at > (select max(_rejected_at) from {{ this }})
{% endif %}
