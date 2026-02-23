{{
    config(
        materialized='incremental',
        unique_key='_reject_id',
        tags=['zone:transient', 'rejects']
    )
}}

with source as (
    {% if target.name == 'dev' %}
        select * from {{ ref('raw_orders') }}
    {% else %}
        select * from {{ source('fivetran_raw', 'orders') }}
    {% endif %}
),

classified as (
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
        case
            when order_id is null then 'order_id is null'
            when customer_id is null then 'customer_id is null'
            when order_date is null then 'order_date is null'
            when total_amount is null then 'total_amount is null'
            else null
        end as _reject_reason,
        current_timestamp()                                                                 as _rejected_at,
        '{{ invocation_id }}'                                                               as _batch_id,
        {{ dbt_utils.generate_surrogate_key(['order_id', 'customer_id', 'order_date']) }}   as _reject_id
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
