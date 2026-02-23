{#
=============================================================================
  Observability macros — dbt Query Tag instrumentation
=============================================================================

  Two macros work together to give every Snowflake query a structured context
  tag that appears in QUERY_HISTORY. This replaces custom log tables with
  native Snowflake audit data.

  QUERY_HISTORY then becomes your N_LOG_EXECUTION equivalent:
    - Timing (start_time, end_time, execution_time) — native
    - Row counts (rows_inserted, rows_updated, rows_deleted) — native
    - Status + error message — native
    - Model name, env, invocation_id, Airflow run ID — injected via QUERY_TAG

  Usage:
    - set_job_query_tag  → called once via on-run-start in dbt_project.yml
    - set_model_query_tag → called per model via +pre-hook in dbt_project.yml

  The resulting view V_DBT_EXECUTION_LOG (in _DB_UTILS.PUBLIC) reconstructs
  the full log by joining QUERY_TAG context with QUERY_HISTORY columns.
=============================================================================
#}


{#
  set_job_query_tag
  -----------------
  Called ONCE at the start of a dbt invocation (on-run-start).
  Sets session-level context that every subsequent query inherits.

  What it injects into QUERY_HISTORY.QUERY_TAG:
    - invocation_id   : dbt's unique run identifier (links all models in one build)
    - job             : human-readable job name (dbt_build_prod, dbt_build_dev, ...)
    - env             : target name (dev / uat / prod / ci)
    - airflow_run_id  : Airflow DAG run ID if triggered from Airflow, else "manual"
    - github_run_id   : GitHub Actions run ID if triggered from CI, else "local"

  This tag is overridden per-model by set_model_query_tag, but acts as
  the fallback for any queries that run outside of model pre-hooks (e.g.,
  on-run-start queries themselves, source freshness checks).
#}
{% macro set_job_query_tag() %}
    {%- set tag = '{'
        ~ '"invocation_id":"' ~ invocation_id ~ '",'
        ~ '"job":"dbt_build_' ~ target.name ~ '",'
        ~ '"env":"' ~ target.name ~ '",'
        ~ '"airflow_run_id":"' ~ env_var("AIRFLOW_RUN_ID", "manual") ~ '",'
        ~ '"github_run_id":"' ~ env_var("GITHUB_RUN_ID", "local") ~ '"'
        ~ '}' -%}
    alter session set query_tag = '{{ tag }}';
{% endmacro %}


{#
  set_model_query_tag
  -------------------
  Called BEFORE every model's SQL via +pre-hook in dbt_project.yml.
  Overrides the session tag with model-level context so the CTAS/MERGE
  query that dbt executes carries the model name in QUERY_HISTORY.

  What it adds on top of the job tag:
    - model         : model name (e.g. "dim_customers", "fct_orders")
    - schema        : target schema (e.g. "gold", "silver")
    - materialized  : materialization type (table, incremental, view, ephemeral)

  This is what allows you to query:
    SELECT model, duration_seconds, rows_inserted
    FROM _DB_UTILS.PUBLIC.V_DBT_EXECUTION_LOG
    WHERE env = 'prod'
    ORDER BY duration_seconds DESC;

  NOTE: `this` and `config` are available in pre-hook context because
  dbt resolves them before calling the hook.
#}
{% macro set_model_query_tag() %}
    {%- set tag = '{'
        ~ '"invocation_id":"' ~ invocation_id ~ '",'
        ~ '"job":"dbt_build_' ~ target.name ~ '",'
        ~ '"env":"' ~ target.name ~ '",'
        ~ '"model":"' ~ this.name ~ '",'
        ~ '"schema":"' ~ this.schema ~ '",'
        ~ '"materialized":"' ~ config.get("materialized", "unknown") ~ '",'
        ~ '"airflow_run_id":"' ~ env_var("AIRFLOW_RUN_ID", "manual") ~ '"'
        ~ '}' -%}
    alter session set query_tag = '{{ tag }}';
{% endmacro %}
