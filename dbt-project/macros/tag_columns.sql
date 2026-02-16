{#
  Reusable macro to add metadata/tagging columns.
  Used in Bronze zone to tag data with source system, domain, and sensitivity.

  Usage in a model:
    select
        col1, col2,
        {{ add_metadata_columns('fivetran', 'customer', 'pii') }}
    from source
#}
{%- macro add_metadata_columns(source_system, domain, sensitivity) -%}
    '{{ source_system }}' as _source_system,
    '{{ domain }}' as _domain,
    '{{ sensitivity }}' as _sensitivity_tag,
    current_timestamp() as _processed_at,
    '{{ invocation_id }}' as _batch_id
{%- endmacro -%}
