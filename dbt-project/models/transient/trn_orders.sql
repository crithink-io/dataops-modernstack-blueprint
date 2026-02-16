{{
    config(
        materialized='table',
        tags=['zone:transient']
    )
}}

with source as (
    {% if target.name == 'dev' %}
        select * from {{ ref('raw_orders') }}
    {% else %}
        select * from {{ source('fivetran_raw', 'orders') }}
    {% endif %}
),

validated as (
    select
        order_id,
        customer_id,
        order_date,
        status,
        total_amount,
        shipping_address,
        billing_address,
        payment_method,
        created_at,
        updated_at,
        -- Technical validation
        case
            when order_id is null then false
            when customer_id is null then false
            when order_date is null then false
            when total_amount is null then false
            else true
        end as _is_valid,
        current_timestamp() as _loaded_at,
        '{{ invocation_id }}' as _batch_id
    from source
)

select * from validated
