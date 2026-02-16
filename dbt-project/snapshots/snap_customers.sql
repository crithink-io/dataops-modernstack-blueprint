{% snapshot snap_customers %}
{{
    config(
        target_schema='bronze',
        target_database=target.database,
        unique_key='customer_id',
        strategy='timestamp',
        updated_at='updated_at',
        invalidate_hard_deletes=true,
        tags=['zone:bronze', 'scd:type2']
    )
}}

-- SCD Type 2 snapshot of cleaned customer data.
-- Tracks changes over time with valid_from / valid_to semantics.
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
    updated_at
from {{ ref('slv_customers') }}

{% endsnapshot %}
