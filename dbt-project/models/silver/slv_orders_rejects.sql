{{
    config(
        materialized='incremental',
        unique_key='_reject_id',
        tags=['zone:silver', 'rejects']
    )
}}

with validated as (
    select * from {{ ref('slv_orders_validated') }}
),

classified as (
    select
        order_id,
        customer_id,
        order_date,
        status,
        total_amount,
        _reject_reason,
        _silver_processed_at,
        current_timestamp() as _rejected_at,
        {{ dbt_utils.generate_surrogate_key(['order_id', 'customer_id']) }} as _reject_id
    from validated
    where _is_business_valid = false
),

final as (
    select * from classified
    {% if is_incremental() %}
        where _silver_processed_at > (select max(_rejected_at) from {{ this }})
    {% endif %}
)

select * from final
