{{
    config(
        materialized='ephemeral'
    )
}}

with bronze as (
    select * from {{ ref('brz_customers') }}
),

deduplicated as (
    select
        *,
        row_number() over (
            partition by customer_id
            order by _bronze_inserted_at desc
        ) as _row_num
    from bronze
),

latest as (
    select * from deduplicated where _row_num = 1
),

standardized as (
    select
        customer_id,
        initcap(trim(first_name)) as first_name,
        initcap(trim(last_name)) as last_name,
        lower(trim(email)) as email,
        trim(phone) as phone,
        trim(address) as address,
        initcap(trim(city)) as city,
        upper(trim(state)) as state_code,
        trim(zip_code) as postal_code,
        upper(trim(country)) as country_code,
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
            when email not like '%@%.%' then false
            when length(trim(postal_code)) < 3 then false
            when country_code is null or trim(country_code) = '' then false
            else true
        end as _is_business_valid,
        case
            when email not like '%@%.%' then 'invalid email format'
            when length(trim(postal_code)) < 3 then 'invalid postal code'
            when country_code is null or trim(country_code) = '' then 'missing country code'
            else null
        end as _reject_reason
    from standardized
)

select * from validated
