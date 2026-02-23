{{
    config(
        materialized='incremental',
        unique_key='_reject_id',
        tags=['zone:transient', 'rejects']
    )
}}

with source as (
    {% if target.name == 'dev' %}
        select * from {{ ref('raw_order_items') }}
    {% else %}
        select * from {{ source('fivetran_raw', 'order_items') }}
    {% endif %}
),

classified as (
    select
        order_item_id,
        order_id,
        product_id,
        quantity,
        unit_price,
        total_price,
        discount_amount,
        created_at,
        case
            when order_item_id is null then 'order_item_id is null'
            when order_id is null then 'order_id is null'
            when product_id is null then 'product_id is null'
            when quantity is null then 'quantity is null'
            else null
        end as _reject_reason,
        current_timestamp()                                                                     as _rejected_at,
        '{{ invocation_id }}'                                                                   as _batch_id,
        {{ dbt_utils.generate_surrogate_key(['order_item_id', 'order_id', 'product_id']) }}     as _reject_id
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
