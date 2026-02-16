{{
    config(
        materialized='ephemeral'
    )
}}

with bronze as (
    select * from {{ ref('brz_orders') }}
),

deduplicated as (
    select
        *,
        row_number() over (
            partition by order_id
            order by _bronze_inserted_at desc
        ) as _row_num
    from bronze
),

latest as (
    select * from deduplicated where _row_num = 1
),

standardized as (
    select
        order_id,
        customer_id,
        order_date,
        upper(trim(status)) as status,
        total_amount,
        trim(shipping_address) as shipping_address,
        trim(billing_address) as billing_address,
        upper(trim(payment_method)) as payment_method,
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
            when order_date is null then false
            when total_amount <= 0 then false
            when status not in ('COMPLETED', 'SHIPPED', 'PROCESSING', 'CANCELLED', 'PENDING') then false
            else true
        end as _is_business_valid,
        case
            when order_date is null then 'missing order date'
            when total_amount <= 0 then 'invalid total amount'
            when status not in ('COMPLETED', 'SHIPPED', 'PROCESSING', 'CANCELLED', 'PENDING') then 'unknown order status'
            else null
        end as _reject_reason
    from standardized
)

select * from validated
