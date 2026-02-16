{{
    config(
        materialized='table',
        tags=['zone:transient']
    )
}}

with source as (
    {% if target.name == 'dev' %}
        select * from {{ ref('raw_products') }}
    {% else %}
        select * from {{ source('fivetran_raw', 'products') }}
    {% endif %}
),

validated as (
    select
        product_id,
        product_name,
        category,
        subcategory,
        brand,
        price,
        cost,
        description,
        is_active,
        created_at,
        updated_at,
        -- Technical validation
        case
            when product_id is null then false
            when product_name is null then false
            when price is null then false
            when cost is null then false
            else true
        end as _is_valid,
        current_timestamp() as _loaded_at,
        '{{ invocation_id }}' as _batch_id
    from source
)

select * from validated
