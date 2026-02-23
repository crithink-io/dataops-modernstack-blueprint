{{
    config(
        materialized='incremental',
        unique_key='_bronze_sk',
        incremental_strategy='append',
        tags=['zone:bronze', 'sensitivity:pii', 'domain:customer']
    )
}}

with source as (
    select * from {{ ref('trn_customers') }}
    where _is_valid = true
    {% if is_incremental() %}
        and _loaded_at > (select coalesce(max(_loaded_at), '1900-01-01') from {{ this }})
    {% endif %}
),

final as (
    select
        customer_id,
        first_name,
        last_name,
        email,
        phone,
        address,
        city,
        state,
        zip_code,
        country,
        created_at,
        updated_at,
        -- Carry forward transient metadata
        _loaded_at,
        _batch_id,
        -- Bronze-specific tagging
        'fivetran'                                                              as _source_system,
        'customer'                                                              as _domain,
        'pii'                                                                   as _sensitivity_tag,
        current_timestamp()                                                     as _bronze_inserted_at,
        {{ dbt_utils.generate_surrogate_key(['customer_id', '_batch_id']) }}    as _bronze_sk
    from source
)

select * from final
