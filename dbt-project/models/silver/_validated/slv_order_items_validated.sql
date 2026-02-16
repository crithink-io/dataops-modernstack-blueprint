{{
    config(
        materialized='ephemeral'
    )
}}

with bronze as (
    select * from {{ ref('brz_order_items') }}
),

deduplicated as (
    select
        *,
        row_number() over (
            partition by order_item_id
            order by _bronze_inserted_at desc
        ) as _row_num
    from bronze
),

latest as (
    select * from deduplicated where _row_num = 1
),

standardized as (
    select
        order_item_id,
        order_id,
        product_id,
        quantity,
        unit_price,
        total_price,
        created_at,
        updated_at,
        _source_system,
        _domain,
        _sensitivity_tag,
        current_timestamp() as _silver_processed_at
    from latest
),

validated as (
    select
        *,
        case
            when quantity <= 0 then false
            when unit_price <= 0 then false
            when total_price <= 0 then false
            else true
        end as _is_business_valid,
        case
            when quantity <= 0 then 'invalid quantity'
            when unit_price <= 0 then 'invalid unit price'
            when total_price <= 0 then 'invalid total price'
            else null
        end as _reject_reason
    from standardized
)

select * from validated
