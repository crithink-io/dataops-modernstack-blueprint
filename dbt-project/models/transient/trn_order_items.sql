{{
    config(
        materialized='table',
        tags=['zone:transient']
    )
}}

with source as (
    {% if target.name == 'dev' %}
        select * from {{ ref('raw_order_items') }}
    {% else %}
        select * from {{ source('fivetran_raw', 'order_items') }}
    {% endif %}
),

validated as (
    select
        order_item_id,
        order_id,
        product_id,
        quantity,
        unit_price,
        total_price,
        discount_amount,
        created_at,
        -- Technical validation
        case
            when order_item_id is null then false
            when order_id is null then false
            when product_id is null then false
            when quantity is null then false
            else true
        end as _is_valid,
        current_timestamp() as _loaded_at,
        '{{ invocation_id }}' as _batch_id
    from source
)

select * from validated
