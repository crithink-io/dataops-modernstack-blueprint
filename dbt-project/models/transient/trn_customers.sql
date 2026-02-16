{{
    config(
        materialized='table',
        tags=['zone:transient']
    )
}}

with source as (
    {% if target.name == 'dev' %}
        select * from {{ ref('raw_customers') }}
    {% else %}
        select * from {{ source('fivetran_raw', 'customers') }}
    {% endif %}
),

validated as (
    select
        customer_id,
        first_name,
        last_name,
        email,
        phone,
        address,
        city,
        state,
        zip_code,
        country,
        created_at,
        updated_at,
        -- Technical validation
        case
            when customer_id is null then false
            when email is null then false
            when created_at is null then false
            else true
        end as _is_valid,
        current_timestamp() as _loaded_at,
        '{{ invocation_id }}' as _batch_id
    from source
)

select * from validated
