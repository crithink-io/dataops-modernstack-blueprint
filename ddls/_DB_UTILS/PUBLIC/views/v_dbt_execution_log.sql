/*
=============================================================================
  View: _DB_UTILS.PUBLIC.V_DBT_EXECUTION_LOG

  Purpose:
    Reconstructs a full dbt execution log from native Snowflake audit data.
    Replaces the need for a custom N_LOG_EXECUTION table by combining:
      - QUERY_TAG context injected by dbt's observability macros
        (macros/observability.sql in the dbt project)
      - Native timing, row counts, and status from QUERY_HISTORY

  How it works:
    Before each model executes, a dbt pre-hook fires:
      ALTER SESSION SET QUERY_TAG = '{"model":"dim_customers","env":"prod",...}'
    The CTAS/MERGE that dbt runs is then tagged in QUERY_HISTORY.
    This view reads that tag + joins native columns to reconstruct the log.

  Columns sourced from QUERY_TAG (injected by macros):
    invocation_id   — dbt's unique run ID (links all models in one build)
    job             — e.g., "dbt_build_prod"
    env             — target name (dev / uat / prod / ci)
    model           — dbt model name (e.g., "dim_customers")
    schema          — target schema (e.g., "gold")
    materialized    — materialization type (table / incremental / view)
    airflow_run_id  — Airflow DAG run ID, or "manual"

  Columns sourced from QUERY_HISTORY (native Snowflake, no custom logging):
    snowflake_query_id  — Snowflake's QUERY_ID (unique per query)
    start_time          — When the query started
    end_time            — When the query ended
    duration_seconds    — Execution time in seconds
    status              — SUCCESS / FAIL
    error_code          — Snowflake error code on failure
    error_message       — Full error message on failure
    rows_inserted       — Rows written (CTAS)
    rows_updated        — Rows updated (MERGE)
    rows_deleted        — Rows deleted (MERGE with deletes)
    event_sequence      — Order of models within one invocation

  Latency:
    ACCOUNT_USAGE.QUERY_HISTORY has 45 min – 3 h latency.
    For real-time (same run monitoring), use V_DBT_EXECUTION_LOG_REALTIME below.

  Usage:
    -- All models from a specific Airflow run
    SELECT model, duration_seconds, status, rows_inserted
    FROM _DB_UTILS.PUBLIC.V_DBT_EXECUTION_LOG
    WHERE airflow_run_id = 'scheduled__2024-02-20T06:00:00+00:00'
    ORDER BY event_sequence;

    -- Slowest models in prod (last 30 days)
    SELECT model, AVG(duration_seconds) AS avg_sec, COUNT(*) AS runs
    FROM _DB_UTILS.PUBLIC.V_DBT_EXECUTION_LOG
    WHERE env = 'prod' AND status = 'SUCCESS'
      AND start_time >= DATEADD(day, -30, CURRENT_TIMESTAMP())
    GROUP BY model
    ORDER BY avg_sec DESC;

    -- All failures this week
    SELECT invocation_id, model, error_message, start_time
    FROM _DB_UTILS.PUBLIC.V_DBT_EXECUTION_LOG
    WHERE status = 'FAIL'
      AND start_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
    ORDER BY start_time DESC;
=============================================================================
*/

CREATE OR REPLACE VIEW _DB_UTILS.PUBLIC.V_DBT_EXECUTION_LOG AS
SELECT
    -- ── Context injected via QUERY_TAG (from macros/observability.sql) ──
    TRY_PARSE_JSON(qh.QUERY_TAG):"invocation_id"::VARCHAR   AS invocation_id,
    TRY_PARSE_JSON(qh.QUERY_TAG):"job"::VARCHAR              AS job,
    TRY_PARSE_JSON(qh.QUERY_TAG):"env"::VARCHAR              AS env,
    TRY_PARSE_JSON(qh.QUERY_TAG):"model"::VARCHAR            AS model,
    TRY_PARSE_JSON(qh.QUERY_TAG):"schema"::VARCHAR           AS model_schema,
    TRY_PARSE_JSON(qh.QUERY_TAG):"materialized"::VARCHAR     AS materialized,
    TRY_PARSE_JSON(qh.QUERY_TAG):"airflow_run_id"::VARCHAR   AS airflow_run_id,

    -- ── Native Snowflake audit data (no custom logging needed) ──────────
    qh.QUERY_ID                                              AS snowflake_query_id,
    qh.START_TIME,
    qh.END_TIME,
    ROUND(qh.EXECUTION_TIME / 1000.0, 2)                    AS duration_seconds,
    qh.EXECUTION_STATUS                                      AS status,
    qh.ERROR_CODE,
    qh.ERROR_MESSAGE,
    qh.ROWS_INSERTED,
    qh.ROWS_UPDATED,
    qh.ROWS_DELETED,
    qh.ROWS_PRODUCED,
    qh.QUERY_TYPE,

    -- ── Derived: order of model executions within one invocation ────────
    ROW_NUMBER() OVER (
        PARTITION BY TRY_PARSE_JSON(qh.QUERY_TAG):"invocation_id"::VARCHAR
        ORDER BY qh.START_TIME
    )                                                        AS event_sequence

FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY qh
WHERE qh.QUERY_TAG IS NOT NULL
  AND TRY_PARSE_JSON(qh.QUERY_TAG):"invocation_id" IS NOT NULL
  AND TRY_PARSE_JSON(qh.QUERY_TAG):"model"         IS NOT NULL
  AND qh.QUERY_TYPE IN (
      'CREATE_TABLE_AS_SELECT',
      'MERGE',
      'INSERT',
      'UPDATE',
      'DELETE'
  );


/*
=============================================================================
  View: _DB_UTILS.PUBLIC.V_DBT_EXECUTION_LOG_REALTIME

  Purpose:
    Same as V_DBT_EXECUTION_LOG but reads from INFORMATION_SCHEMA instead
    of ACCOUNT_USAGE. No latency — shows queries from the last 7 days in
    real time. Use this during or immediately after a dbt run.

  Trade-off vs V_DBT_EXECUTION_LOG:
    - No latency (real-time)     vs  up to 3h latency
    - 7-day retention            vs  1-year retention
    - Per-session function call  vs  account-wide table

  Typical use: Airflow sensor task that checks status right after dbt finishes.
=============================================================================
*/

CREATE OR REPLACE VIEW _DB_UTILS.PUBLIC.V_DBT_EXECUTION_LOG_REALTIME AS
SELECT
    TRY_PARSE_JSON(qh.QUERY_TAG):"invocation_id"::VARCHAR   AS invocation_id,
    TRY_PARSE_JSON(qh.QUERY_TAG):"job"::VARCHAR              AS job,
    TRY_PARSE_JSON(qh.QUERY_TAG):"env"::VARCHAR              AS env,
    TRY_PARSE_JSON(qh.QUERY_TAG):"model"::VARCHAR            AS model,
    TRY_PARSE_JSON(qh.QUERY_TAG):"schema"::VARCHAR           AS model_schema,
    TRY_PARSE_JSON(qh.QUERY_TAG):"materialized"::VARCHAR     AS materialized,
    TRY_PARSE_JSON(qh.QUERY_TAG):"airflow_run_id"::VARCHAR   AS airflow_run_id,
    qh.QUERY_ID                                              AS snowflake_query_id,
    qh.START_TIME,
    qh.END_TIME,
    ROUND(qh.TOTAL_ELAPSED_TIME / 1000.0, 2)                AS duration_seconds,
    qh.EXECUTION_STATUS                                      AS status,
    qh.ERROR_CODE,
    qh.ERROR_MESSAGE,
    qh.ROWS_INSERTED,
    qh.ROWS_UPDATED,
    qh.ROWS_DELETED,
    qh.ROWS_PRODUCED,
    qh.QUERY_TYPE,
    ROW_NUMBER() OVER (
        PARTITION BY TRY_PARSE_JSON(qh.QUERY_TAG):"invocation_id"::VARCHAR
        ORDER BY qh.START_TIME
    )                                                        AS event_sequence
FROM TABLE(
    INFORMATION_SCHEMA.QUERY_HISTORY(
        DATE_RANGE_START => DATEADD(day, -7, CURRENT_TIMESTAMP()),
        RESULT_LIMIT     => 10000
    )
) qh
WHERE qh.QUERY_TAG IS NOT NULL
  AND TRY_PARSE_JSON(qh.QUERY_TAG):"invocation_id" IS NOT NULL
  AND TRY_PARSE_JSON(qh.QUERY_TAG):"model"         IS NOT NULL
  AND qh.QUERY_TYPE IN (
      'CREATE_TABLE_AS_SELECT',
      'MERGE',
      'INSERT',
      'UPDATE',
      'DELETE'
  );


/*
=============================================================================
  Grant permissions — adjust role names to match your RBAC setup.
=============================================================================
*/
GRANT REFERENCES ON VIEW _DB_UTILS.PUBLIC.V_DBT_EXECUTION_LOG          TO ROLE DBT_CI_ROLE;
GRANT REFERENCES ON VIEW _DB_UTILS.PUBLIC.V_DBT_EXECUTION_LOG_REALTIME TO ROLE DBT_CI_ROLE;
-- Add ANALYST_ROLE or BI_ROLE grants here if dashboards need to read this view.
