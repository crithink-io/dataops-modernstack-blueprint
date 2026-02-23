{{
    config(
        materialized='incremental',
        unique_key='_bronze_sk',
        incremental_strategy='append',
        tags=['zone:bronze', 'sensitivity:confidential', 'domain:order']
    )
}}

with source as (
    select * from {{ ref('trn_orders') }}
    where _is_valid = true
    {% if is_incremental() %}
        and _loaded_at > (select coalesce(max(_loaded_at), '1900-01-01') from {{ this }})
    {% endif %}
),

final as (
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
        -- Carry forward transient metadata
        _loaded_at,
        _batch_id,
        -- Bronze-specific tagging
        'fivetran'                                                          as _source_system,
        'order'                                                             as _domain,
        'confidential'                                                      as _sensitivity_tag,
        current_timestamp()                                                 as _bronze_inserted_at,
        {{ dbt_utils.generate_surrogate_key(['order_id', '_batch_id']) }}   as _bronze_sk
    from source
)

select * from final
