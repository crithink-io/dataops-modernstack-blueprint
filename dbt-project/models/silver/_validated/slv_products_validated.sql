{{
    config(
        materialized='ephemeral'
    )
}}

with bronze as (
    select * from {{ ref('brz_products') }}
),

deduplicated as (
    select
        *,
        row_number() over (
            partition by product_id
            order by _bronze_inserted_at desc
        ) as _row_num
    from bronze
),

latest as (
    select * from deduplicated where _row_num = 1
),

standardized as (
    select
        product_id,
        initcap(trim(product_name)) as product_name,
        trim(description) as description,
        initcap(trim(category)) as category,
        initcap(trim(subcategory)) as subcategory,
        initcap(trim(brand)) as brand,
        price,
        cost,
        is_active,
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
            when price <= 0 then false
            when cost < 0 then false
            when cost > price then false
            else true
        end as _is_business_valid,
        case
            when price <= 0 then 'invalid price'
            when cost < 0 then 'invalid cost'
            when cost > price then 'cost exceeds price'
            else null
        end as _reject_reason
    from standardized
)

select * from validated
