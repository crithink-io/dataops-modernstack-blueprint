{#
  Row count validation macro for transient zone.
  Compares row counts between a source and target relation.
  Returns the difference (source - target). Zero means match.

  Usage:
    {% set diff = validate_row_counts(source('fivetran_raw', 'customers'), ref('trn_customers')) %}
#}
{%- macro validate_row_counts(source_relation, target_relation) -%}
    {% set source_count_query %}
        select count(*) as cnt from {{ source_relation }}
    {% endset %}

    {% set target_count_query %}
        select count(*) as cnt from {{ target_relation }}
    {% endset %}

    {% set source_count = run_query(source_count_query).columns[0].values()[0] %}
    {% set target_count = run_query(target_count_query).columns[0].values()[0] %}

    {% do log("Row count validation:", info=true) %}
    {% do log("  Source (" ~ source_relation ~ "): " ~ source_count ~ " rows", info=true) %}
    {% do log("  Target (" ~ target_relation ~ "): " ~ target_count ~ " rows", info=true) %}

    {% if source_count != target_count %}
        {% do log("  WARNING: Row count mismatch! Difference: " ~ (source_count - target_count), info=true) %}
    {% else %}
        {% do log("  Row counts match.", info=true) %}
    {% endif %}

    {{ return(source_count - target_count) }}
{%- endmacro -%}
