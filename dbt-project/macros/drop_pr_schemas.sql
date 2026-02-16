{#
  Drops a PR-specific schema from the _db_utils database.
  Called by the CI teardown workflow after a PR is closed.
  Usage: dbt run-operation drop_pr_schemas --args "{pr_schema_name: 'PR_42__A1B2C3D'}"
#}
{%- macro drop_pr_schemas(pr_schema_name=none) -%}
  {% set ci_db = env_var('SNOWFLAKE_CI_DATABASE', '_DB_UTILS') %}
  {% set schema_to_drop = pr_schema_name if pr_schema_name else target.schema %}

  {% do log("Dropping schema: " ~ ci_db ~ "." ~ schema_to_drop, info=true) %}

  {% set drop_sql = 'drop schema if exists ' ~ adapter.quote(ci_db) ~ '.' ~ adapter.quote(schema_to_drop) ~ ' cascade' %}
  {% do log("DROP SQL: " ~ drop_sql, info=true) %}

  {% do run_query(drop_sql) %}

  {% do log("Schema dropped successfully.", info=true) %}
{%- endmacro -%}
