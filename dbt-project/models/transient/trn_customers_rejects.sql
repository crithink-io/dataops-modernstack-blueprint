{{
    config(
        materialized='incremental',
        unique_key='_reject_id',
        tags=['zone:transient', 'rejects']
    )
}}

with source as (
    {% if target.name == 'dev' %}
        select * from {{ ref('raw_customers') }}
    {% else %}
        select * from {{ source('fivetran_raw', 'customers') }}
    {% endif %}
),

classified as (
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
        case
            when customer_id is null then 'customer_id is null'
            when email is null then 'email is null'
            when created_at is null then 'created_at is null'
            else null
        end as _reject_reason,
        current_timestamp()                                                     as _rejected_at,
        '{{ invocation_id }}'                                                   as _batch_id,
        {{ dbt_utils.generate_surrogate_key(['customer_id', 'email']) }}        as _reject_id
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
