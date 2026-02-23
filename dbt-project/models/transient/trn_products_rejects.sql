{{
    config(
        materialized='incremental',
        unique_key='_reject_id',
        tags=['zone:transient', 'rejects']
    )
}}

with source as (
    {% if target.name == 'dev' %}
        select * from {{ ref('raw_products') }}
    {% else %}
        select * from {{ source('fivetran_raw', 'products') }}
    {% endif %}
),

classified as (
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
        case
            when product_id is null then 'product_id is null'
            when product_name is null then 'product_name is null'
            when price is null then 'price is null'
            when cost is null then 'cost is null'
            else null
        end as _reject_reason,
        current_timestamp()                                                         as _rejected_at,
        '{{ invocation_id }}'                                                       as _batch_id,
        {{ dbt_utils.generate_surrogate_key(['product_id', 'product_name']) }}      as _reject_id
    from source
),

final as (
    select * from classified
    where _reject_reason is not null
    {% if is_incremental() %}
        and _rejected_at > (select max(_rejected_at) from {{ this }})
    {% endif %}
)

select * from final
