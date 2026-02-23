{#
  Calls the _DB_UTILS stored procedure to clone data for CI testing.
  The stored procedure handles:
    - Sampling for lower environments (dev: 10%, uat/prod: full clone)
    - Using a masked-data role for PII protection
    - Zero-copy clones for full copies, CTAS with SAMPLE() for subsets
    - Slim mode: when table_list is provided, clones only specific tables
      instead of scanning entire schemas

  Usage — full clone (first run, no manifest):
    dbt run-operation clone_for_ci --args "{
      source_db: 'APP_DB_DEV',
      source_schema_list: 'TRANSIENT,BRONZE,SILVER,GOLD,GOLD_ANALYTICS',
      target_schema: 'PR_42__A1B2C3D',
      env_type: 'dev',
      sample_pct: 10,
      role_name: 'DBT_CI_MASKED_ROLE',
      table_list: '*'
    }"

  Usage — slim clone (manifest available, specific tables only):
    dbt run-operation clone_for_ci --args "{
      source_db: 'APP_DB_DEV',
      source_schema_list: '',
      target_schema: 'PR_42__A1B2C3D',
      env_type: 'dev',
      sample_pct: 0,
      role_name: 'DBT_CI_MASKED_ROLE',
      table_list: 'SILVER.SLV_CUSTOMERS,GOLD.DIM_CUSTOMERS'
    }"
#}
{%- macro clone_for_ci(source_db, source_schema_list, target_schema, env_type, sample_pct, role_name, table_list='*') -%}
    {% set ci_db = env_var('SNOWFLAKE_CI_DATABASE', '_DB_UTILS') %}
    {% set mode = 'slim' if table_list != '*' else 'full' %}

    {% do log("=== Clone for CI ===", info=true) %}
    {% do log("  CI Database:      " ~ ci_db, info=true) %}
    {% do log("  Source DB:        " ~ source_db, info=true) %}
    {% do log("  Mode:             " ~ mode, info=true) %}
    {% if mode == 'full' %}
    {% do log("  Source schemas:   " ~ source_schema_list, info=true) %}
    {% else %}
    {% do log("  Tables:           " ~ table_list, info=true) %}
    {% endif %}
    {% do log("  Target schema:    " ~ target_schema, info=true) %}
    {% do log("  Environment:      " ~ env_type, info=true) %}
    {% do log("  Sample pct:       " ~ sample_pct ~ "%", info=true) %}
    {% do log("  Role:             " ~ role_name, info=true) %}

    {% set sql %}
        call {{ ci_db }}.public.clone_for_ci(
            '{{ source_db }}',
            '{{ source_schema_list }}',
            '{{ target_schema }}',
            '{{ env_type }}',
            {{ sample_pct }},
            '{{ role_name }}',
            '{{ table_list }}'
        )
    {% endset %}

    {% do run_query(sql) %}

    {% do log("Clone for CI completed successfully.", info=true) %}
{%- endmacro -%}
