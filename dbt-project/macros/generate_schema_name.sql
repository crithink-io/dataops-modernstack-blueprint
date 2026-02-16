{#
  Custom schema routing for multi-zone medallion architecture.
  - CI target: all zones flatten into a single PR schema in _db_utils.
  - Dev/UAT/Prod: each zone gets its own schema (transient, bronze, silver, gold, gold_analytics).
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if target.name == 'ci' -%}
        {# In CI, everything goes into the PR schema in _db_utils #}
        {{ target.schema }}
    {%- elif custom_schema_name is not none and custom_schema_name | trim != '' -%}
        {# In dev/uat/prod, use the zone schema directly #}
        {{ custom_schema_name | trim }}
    {%- else -%}
        {{ target.schema }}
    {%- endif -%}
{%- endmacro %}
