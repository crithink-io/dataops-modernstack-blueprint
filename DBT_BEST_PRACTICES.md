# dbt Best Practices — A Practitioner's Guide

**Audience:** Data engineers building production dbt projects on Snowflake.
**Approach:** Factual, concise, pattern-oriented. Every recommendation is explained with *why*, not just *what*.

---

## Table of Contents

1. [Materialization Strategy](#1-materialization-strategy)
2. [Model Design Patterns](#2-model-design-patterns)
3. [Anti-Patterns to Avoid](#3-anti-patterns-to-avoid)
4. [Incremental Models Deep Dive](#4-incremental-models-deep-dive)
5. [Full Refresh](#5-full-refresh)
6. [Testing Strategy](#6-testing-strategy)
7. [Development Workflow](#7-development-workflow)
8. [Slim CI](#8-slim-ci)
9. [Deployment and Scaling](#9-deployment-and-scaling)
10. [Snowflake-Specific Limitations](#10-snowflake-specific-limitations)
11. [dbt Ecosystem: Core, Cloud, and Fusion](#11-dbt-ecosystem-core-cloud-and-fusion)

---

## 1. Materialization Strategy

Materialization controls **how** dbt persists a model in the warehouse. Choosing wrong costs you either compute (rebuilding unnecessarily) or storage (keeping what you don't need).

### Decision Matrix

| Materialization | Use When | Cost Profile | Rebuild Behavior |
|----------------|----------|-------------|-----------------|
| **view** | Data is small (<100K rows), always needs fresh results, or is rarely queried | Low storage, compute on every query | `CREATE OR REPLACE VIEW` every run |
| **table** | Data changes fully each run, downstream models need fast reads, moderate size | Higher storage, compute once per run | `CREATE OR REPLACE TABLE` every run (full rebuild) |
| **incremental** | Large tables (millions+ rows), append-only or slowly changing data, rebuilding is too expensive | Lowest compute per run, growing storage | `INSERT INTO` or `MERGE` — only processes new/changed rows |
| **ephemeral** | Pure logic layer, no one queries it directly, used only as CTE in other models | Zero storage, zero compute on its own | Injected as CTE into downstream models at compile time |
| **snapshot** | Need to track historical changes (SCD Type 2), source data is mutable | Growing storage, small compute per run | Compares current vs previous, inserts changed records with timestamps |

### Rules of Thumb

- **Start with `table`**, move to `incremental` only when rebuild time becomes a problem. Premature incremental models are a top source of bugs.
- **Use `view` for staging/transient models** only if they're lightweight and not referenced by many downstream models. Each downstream query re-executes the view.
- **Use `ephemeral` sparingly.** It's invisible in the warehouse (no table, no view), so you can't query it for debugging. Good for shared validation logic or deduplication CTEs.
- **Never use `view` in the gold layer.** BI tools query gold models repeatedly — a view forces a full recompute every time. Always `table` or `incremental`.
- **Snapshots are not incremental models.** Snapshots track *changes* over time (SCD2). Incremental models append *new data*. Don't confuse them.

### Snowflake-Specific Notes

- **Transient tables** (`{{ config(transient='true') }}`) reduce Snowflake storage costs by disabling Time Travel beyond 1 day and Fail-safe entirely. Use for staging/transient zone models where you don't need 7-day recovery.
- **Clustering** (`{{ config(cluster_by=['date_col']) }}`) helps large incremental tables. Snowflake auto-clusters, but explicit keys improve scan efficiency on filtered queries. Only useful for tables >1TB.

> **Reference:** [dbt Materializations](https://docs.getdbt.com/docs/build/materializations)

---

## 2. Model Design Patterns

### CTE Pattern (Always Use This)

Every model should follow this structure:

```sql
with

source_data as (
    select * from {{ ref('stg_orders') }}
),

transformed as (
    select
        order_id,
        customer_id,
        order_date,
        amount * (1 - discount_pct) as net_amount
    from source_data
    where status != 'cancelled'
),

final as (
    select
        {{ dbt_utils.generate_surrogate_key(['order_id']) }} as order_sk,
        *
    from transformed
)

select * from final
```

**Why:** CTEs are readable, debuggable (you can `select * from source_data` to inspect intermediate steps), and the Snowflake optimizer handles them efficiently — they don't create temp tables.

### Naming Conventions

| Layer | Prefix | Example | Purpose |
|-------|--------|---------|---------|
| Staging/Transient | `stg_` or `trn_` | `trn_customers` | 1:1 with source, light cleaning |
| Intermediate | `int_` | `int_orders_joined` | Complex joins or logic, not exposed to BI |
| Facts | `fct_` | `fct_orders` | Business events with measures |
| Dimensions | `dim_` | `dim_customers` | Descriptive entities |
| Aggregations | `agg_` | `agg_daily_revenue` | Pre-computed rollups for BI |

**Why naming matters:** A developer should know the layer, grain, and purpose of a model from its name alone, without reading the SQL.

### One Source, One Staging Model

Every raw source table gets exactly **one** staging model. All downstream models reference the staging model, never the raw source directly.

```
raw.customers → trn_customers → brz_customers → slv_customers → dim_customers
                 ↑ only place source() is called
```

**Why:** If the source schema changes (column renamed, type changed), you fix it in one place. Without this, the same fix propagates across dozens of models.

### Explicit Column Selection

Never use `SELECT *` in production models (except in staging models selecting from a `source()` or `ref()` with `select *` as the first step in a CTE chain). Always list columns explicitly.

```sql
-- BAD: new upstream columns silently leak into your model
select * from {{ ref('stg_customers') }}

-- GOOD: you control exactly what this model exposes
select
    customer_id,
    first_name,
    last_name,
    email,
    created_at
from {{ ref('stg_customers') }}
```

**Why:** Prevents schema drift — upstream changes don't silently break or bloat downstream models. Also makes lineage and impact analysis meaningful.

### Ref and Source Only

- Use `{{ ref('model_name') }}` for inter-model dependencies.
- Use `{{ source('source_name', 'table_name') }}` for raw data.
- **Never hardcode table names** (`FROM database.schema.table`). This breaks environment isolation (dev/uat/prod) and lineage tracking.

> **Reference:** [dbt Best Practices](https://docs.getdbt.com/best-practices)

---

## 3. Anti-Patterns to Avoid

### 3.1 — Business Logic in Staging Models

**Problem:** Staging models should only rename, cast, and clean. If you put business logic (calculations, joins, filtering) here, you couple raw data structure to business rules.

```sql
-- BAD: business logic in staging
select
    order_id,
    amount * 1.2 as amount_with_tax,  -- tax calculation doesn't belong here
    case when status = 'C' then 'Completed' end as status_label
from {{ source('raw', 'orders') }}
```

**Fix:** Staging does casting and renaming. Business logic goes in silver/gold.

### 3.2 — Circular Dependencies

**Problem:** Model A refs Model B, Model B refs Model A. dbt cannot build either. This usually happens when two models share logic that should be extracted.

**Fix:** Extract shared logic into a third model (often ephemeral) that both reference.

### 3.3 — Overusing Incremental

**Problem:** Making a model incremental "just in case" when it processes 10K rows. Incremental adds complexity (merge logic, `is_incremental()` conditions) and risk (missed deletes, late-arriving data). It only saves time when the table is large enough that a full rebuild is painful.

**Rule:** Don't go incremental until full rebuild takes >5 minutes or the table has >10M rows. Measure first.

### 3.4 — Giant Models (>200 Lines of SQL)

**Problem:** A single model with 300+ lines of SQL joining 10 tables, with complex CASE statements and window functions. Impossible to test, debug, or reuse.

**Fix:** Break it into intermediate models. Each model should do one conceptual thing: join, filter, aggregate, or transform. Chain them with `ref()`.

### 3.5 — Misunderstanding Source Freshness

**Problem:** Treating `dbt source freshness` as if it detects data changes. It doesn't. It's a **staleness check**, not a change detection mechanism.

**What it actually does:** Runs `SELECT MAX(loaded_at_field) FROM source_table` and compares the result against the current time. That's it — a single `MAX()` query on one column.

**What it does NOT do:**
- Does not detect what rows changed (use Snowflake Streams for that)
- Does not listen for events or triggers (nothing runs until you invoke `dbt source freshness`)
- Does not verify data correctness (a Fivetran sync can complete with empty or corrupt data — freshness won't catch it)
- Does not run automatically (you must schedule it yourself)

**What it's useful for:** Preventing dbt from building on stale data. If Fivetran hasn't synced in 24 hours, freshness fails and blocks the pipeline. Without it, dbt silently rebuilds on yesterday's data and nobody notices.

**Requirement:** Your source table must have a timestamp column written by your ELT tool (e.g., `_fivetran_synced`, `_loaded_at`). If there's no such column, freshness can't work.

```yaml
sources:
  - name: fivetran_raw
    freshness:
      warn_after: {count: 12, period: hour}
      error_after: {count: 24, period: hour}
    loaded_at_field: _fivetran_synced  # ← MAX() is run on this column
    tables:
      - name: customers
```

```bash
# Use as a pre-build gate — fail fast if sources are stale
dbt source freshness && dbt build
```

**For actual data change detection on Snowflake**, use:

| Need | Tool |
|------|------|
| What rows changed? | Snowflake Streams (`CREATE STREAM ON TABLE`) |
| Trigger dbt on new data? | Snowflake Task + Stream, or Fivetran webhooks |
| Row count sanity check? | Custom macro like `validate_row_counts` or `dbt_expectations` |

Source freshness is a **smoke alarm** — it tells you something might be wrong (no recent data). It doesn't tell you what changed or whether the data is correct.

### 3.6 — No Tests on Primary Keys

**Problem:** Gold models without `unique` and `not_null` tests on the primary key. When a join produces duplicates, the model silently inflates numbers. BI reports wrong data. Nobody notices for weeks.

**Fix:** Every model must have at minimum `unique` + `not_null` on its primary key. Non-negotiable.

### 3.7 — Using `{{ this }}` Without Understanding It

**Problem:** `{{ this }}` refers to the current model's table in the warehouse. In incremental models, it's used to filter for new data. But during a full refresh or first run, `{{ this }}` doesn't exist yet — your SQL will fail if you use it outside `{% if is_incremental() %}`.

```sql
-- BAD: fails on first run
select * from {{ ref('stg_events') }}
where event_date > (select max(event_date) from {{ this }})

-- GOOD: wrapped in is_incremental()
select * from {{ ref('stg_events') }}
{% if is_incremental() %}
    where event_date > (select max(event_date) from {{ this }})
{% endif %}
```

### 3.8 — Storing Secrets in `profiles.yml` or `dbt_project.yml`

**Problem:** Hardcoding passwords, account names, or tokens in files that get committed to Git.

**Fix:** Always use `{{ env_var('SNOWFLAKE_PASSWORD') }}`. No exceptions. Add `.env` to `.gitignore`.

### 3.9 — Running `dbt run` Instead of `dbt build`

**Problem:** `dbt run` executes models but skips tests and snapshots. You deploy code that might fail tests.

**Fix:** Always use `dbt build`. It runs models + tests + snapshots + seeds in DAG order. If a test fails, downstream models don't execute.

### 3.10 — Not Using `--defer` in Development

**Problem:** Running `dbt build` locally builds the entire DAG, even models you didn't change. Slow and expensive.

**Fix:** Use `dbt build --select state:modified+ --defer --state path/to/prod/manifest` to build only what you changed, deferring unchanged models to the production state.

> **Reference:** [dbt Anti-Patterns](https://docs.getdbt.com/best-practices/how-we-style/6-how-we-style-our-sql)

---

## 4. Incremental Models Deep Dive

### How Incremental Works

On first run, dbt creates the full table. On subsequent runs, it only processes rows that match a filter condition (usually a timestamp), then either appends or merges them.

```sql
{{ config(
    materialized='incremental',
    unique_key='event_id',
    incremental_strategy='merge',
    on_schema_change='append_new_columns'
) }}

select
    event_id,
    user_id,
    event_type,
    event_timestamp,
    payload
from {{ ref('stg_events') }}

{% if is_incremental() %}
    where event_timestamp > (select max(event_timestamp) from {{ this }})
{% endif %}
```

### Incremental Strategies on Snowflake

| Strategy | SQL Generated | Use When | Handles Deletes? |
|----------|--------------|----------|-----------------|
| `append` | `INSERT INTO` | Data is append-only, no updates | No |
| `merge` | `MERGE INTO ... WHEN MATCHED THEN UPDATE WHEN NOT MATCHED THEN INSERT` | Data can be updated (late-arriving corrections) | No (unless with `delete+insert`) |
| `delete+insert` | `DELETE WHERE ... ; INSERT INTO` | Reprocess entire partitions (e.g., reload last 3 days) | Yes, within the reprocessed window |
| `microbatch` | Processes data in time-based batches | Very large datasets, need retry granularity | Yes, within each batch |

### When to Choose Each

- **`append`** — Event streams, logs, CDC data that's truly insert-only. Fastest.
- **`merge`** — Most common. Source data can be updated (e.g., order status changes). Requires `unique_key`.
- **`delete+insert`** — When you need to reprocess a time window (e.g., "always reload last 3 days to catch late arrivals"). More expensive but safer.
- **`microbatch`** (dbt 1.9+) — For very large event tables. Processes one time-slice at a time, so a failure only requires retrying one batch, not the whole table.

### Schema Changes in Incremental Models

When upstream adds a column, your incremental model's existing table doesn't have that column. The `on_schema_change` config controls this:

| Setting | Behavior |
|---------|----------|
| `ignore` (default) | New columns are silently dropped. Existing columns unchanged. |
| `append_new_columns` | New columns are added to the table (ALTERed). Safe choice. |
| `sync_all_columns` | Adds new columns AND drops removed columns. Dangerous — can delete data. |
| `fail` | Build fails if schema doesn't match. Safest for production. |

**Recommendation:** Use `append_new_columns` for most models. Use `fail` for critical fact tables where schema changes should be reviewed.

### Late-Arriving Data

If your incremental filter is `where event_timestamp > max(event_timestamp) from {{ this }}`, any row with a timestamp before the current max is missed forever. This is a common bug.

**Fix:** Use a lookback window:

```sql
{% if is_incremental() %}
    where event_timestamp > (
        select dateadd(day, -3, max(event_timestamp)) from {{ this }}
    )
{% endif %}
```

This reprocesses the last 3 days on every run. Combined with `merge` strategy and `unique_key`, duplicates are handled automatically.

> **Reference:** [dbt Incremental Models](https://docs.getdbt.com/docs/build/incremental-models)

---

## 5. Full Refresh

### What It Does

`dbt build --full-refresh` drops and recreates all incremental models from scratch, as if they were tables. Snapshots are NOT affected (they would lose history).

### When to Use It

| Scenario | Full Refresh? |
|----------|:------------:|
| Schema change that `on_schema_change` can't handle (column type change, rename) | Yes |
| Incremental logic bug that produced wrong data | Yes |
| Late-arriving data that fell outside the lookback window | Yes |
| Switching incremental strategy (e.g., `append` → `merge`) | Yes |
| First deploy to a new environment | Not needed (first run is always full) |
| Regular scheduled runs | **No** — defeats the purpose of incremental |
| After a source backfill | Yes, for affected models |

### How to Run It Safely

```bash
# Full refresh a single model (not the whole project)
dbt build --select my_incremental_model --full-refresh

# Full refresh a model and everything downstream
dbt build --select my_incremental_model+ --full-refresh

# Full refresh everything (use sparingly)
dbt build --full-refresh
```

**Warning:** Full refresh on large incremental tables is expensive. A table with 1B rows that normally processes 100K rows incrementally will now rebuild all 1B rows. Run during off-peak hours.

### Snapshots and Full Refresh

`--full-refresh` does NOT affect snapshots by default. This is intentional — snapshots contain historical data that would be destroyed. If you truly need to rebuild a snapshot (e.g., wrong config), use `dbt snapshot --select snap_name --full-refresh` explicitly.

> **Reference:** [dbt Full Refresh](https://docs.getdbt.com/reference/commands/build#the---full-refresh-flag)

---

## 6. Testing Strategy

### Test Hierarchy

Tests should be layered, from cheapest to most expensive:

| Level | Test Type | Cost | Example |
|-------|----------|------|---------|
| 1 | **Schema tests** (YAML) | Cheap — single column scan | `not_null`, `unique`, `accepted_values` |
| 2 | **Relationship tests** | Moderate — FK lookup | `relationships` (every `customer_id` in orders exists in customers) |
| 3 | **Singular tests** (SQL) | Variable — custom query | Grain test, cross-model consistency |
| 4 | **dbt_expectations** | Variable — statistical checks | `expect_column_values_to_be_between`, `expect_table_row_count_to_be_between` |
| 5 | **Source freshness** | Cheap — single `MAX()` query | `dbt source freshness` — checks if data arrived recently, not what changed (see [section 3.5](#35--misunderstanding-source-freshness)) |

### Minimum Tests Per Model

Every model should have **at minimum**:

```yaml
models:
  - name: fct_orders
    columns:
      - name: order_sk
        data_tests:
          - not_null
          - unique
      - name: customer_id
        data_tests:
          - not_null
          - relationships:
              to: ref('dim_customers')
              field: customer_id
```

**Primary key:** `unique` + `not_null`. Always.
**Foreign keys:** `relationships` test. Catches orphan records (broken joins).

### Test Severity

Not all test failures should block deployment:

```yaml
- name: email
  data_tests:
    - not_null:
        severity: warn  # don't block, but log it
    - unique:
        severity: error  # block deployment
```

Use `warn` for data quality issues you want to track but can't fix immediately. Use `error` (default) for invariants that must hold.

### Singular Tests (Custom SQL)

For business rules that can't be expressed as schema tests:

```sql
-- tests/fct_orders_no_negative_revenue.sql
-- This test fails if any rows are returned
select order_id, net_amount
from {{ ref('fct_orders') }}
where net_amount < 0
```

### When Tests Run

- `dbt build` runs tests immediately after each model. If a test fails, downstream models are skipped.
- `dbt test` runs all tests without building models (useful for monitoring).
- In CI, tests run as part of `dbt build --select state:modified+` — only testing what changed.

> **Reference:** [dbt Testing](https://docs.getdbt.com/docs/build/data-tests)

---

## 7. Development Workflow

### Local Development Checklist

```bash
# 1. Pull latest main
git checkout main && git pull

# 2. Create feature branch
git checkout -b feature/add-customer-ltv

# 3. Activate environment
source venv/bin/activate

# 4. Work in dbt project directory
cd dbt-project

# 5. Build only what you changed (fast feedback loop)
dbt build --select my_new_model+

# 6. Build with state comparison (if you have a prod manifest)
dbt build --select state:modified+ --defer --state target/prod-manifest/

# 7. Check compiled SQL (useful for debugging)
dbt compile --select my_new_model
cat target/compiled/project_name/models/gold/my_new_model.sql

# 8. Lint before committing
sqlfluff lint models/gold/my_new_model.sql --config .sqlfluff

# 9. Generate docs to verify lineage
dbt docs generate && dbt docs serve
```

### Selector Syntax Cheat Sheet

| Selector | Meaning |
|----------|---------|
| `dbt build --select my_model` | Build only this model |
| `dbt build --select my_model+` | This model + all downstream |
| `dbt build --select +my_model` | All upstream + this model |
| `dbt build --select +my_model+` | Full lineage (up and downstream) |
| `dbt build --select my_model+2` | This model + 2 levels downstream |
| `dbt build --select tag:gold` | All models tagged `gold` |
| `dbt build --select path:models/gold/` | All models in gold directory |
| `dbt build --select state:modified+` | Modified models + downstream |
| `dbt build --exclude my_model` | Everything except this model |
| `dbt build --select my_model --full-refresh` | Full refresh only this model |

### `dbt build` vs `dbt run` vs `dbt test`

| Command | Models | Tests | Snapshots | Seeds |
|---------|:------:|:-----:|:---------:|:-----:|
| `dbt build` | Yes | Yes | Yes | Yes |
| `dbt run` | Yes | No | No | No |
| `dbt test` | No | Yes | No | No |
| `dbt snapshot` | No | No | Yes | No |
| `dbt seed` | No | No | No | Yes |

**Always use `dbt build`** in production and CI. It respects DAG order and stops on test failure.

### Environment Isolation

Each developer should work in an isolated schema. Use `generate_schema_name` macro:

```sql
-- macros/generate_schema_name.sql
{% macro generate_schema_name(custom_schema_name, node) %}
    {% if target.name == 'dev' %}
        {{ target.schema }}_{{ custom_schema_name | default(target.schema) }}
    {% else %}
        {{ custom_schema_name | default(target.schema) }}
    {% endif %}
{% endmacro %}
```

In dev, models land in `DEV_ANOUAR_GOLD` (developer-prefixed). In prod, they land in `GOLD`.

> **Reference:** [dbt Commands](https://docs.getdbt.com/reference/commands/build)

---

## 8. Slim CI

### What Is Slim CI?

Instead of building the entire dbt project on every PR (expensive, slow), Slim CI builds **only the models that changed** and their downstream dependencies. It compares your PR against the last known good state (the production manifest).

### How It Works

```
1. Download the production manifest.json (artifact from last successful build)
2. Run: dbt build --select state:modified+ --defer --state path/to/prod-manifest/
3. dbt compares your project against the manifest
4. Only modified models + their downstream models are built
5. Unmodified upstream models are "deferred" — they read from production tables
```

### The Key Flags

| Flag | Purpose |
|------|---------|
| `--select state:modified+` | Select only modified models and their downstream dependencies |
| `--defer` | For unmodified upstream models, read from the target defined in `--state` instead of building them |
| `--state path/to/manifest/` | Path to the production manifest.json for comparison |

### What "Modified" Means

`state:modified` detects:
- SQL file content changes (your model code changed)
- Config changes (materialization, tags, schema changed in YAML)
- Macro changes (if a macro used by the model changed)
- Schema YAML changes (test added/removed)

It does NOT detect:
- Source data changes (that's what source freshness is for)
- Environment variable changes
- Package version updates (run full build after `dbt deps`)

### CI Database Isolation

Slim CI should run in an **isolated schema** (not your production database) to avoid polluting real data:

```
Production: APP_DB.GOLD.fct_orders
CI build:   _DB_UTILS.PR_42__A1B2C3D.fct_orders  (isolated PR schema)
```

The `--defer` flag makes unmodified upstream models read from production, so CI only materializes changed models in the isolated schema.

### First Run Problem

On the very first CI run, there's no production manifest to compare against. Every model appears "modified." Handle this gracefully:

```yaml
# In GitHub Actions
- name: Download manifest
  uses: actions/download-artifact@v4
  with:
    name: dbt-manifest-prod
  continue-on-error: true  # first run: no artifact yet, build everything
```

### Cost Savings

| Project Size | Full Build | Slim CI Build | Savings |
|-------------|-----------|--------------|---------|
| 50 models | 5 min | 30 sec (2 modified) | 90% |
| 200 models | 20 min | 2 min (5 modified) | 90% |
| 1000 models | 90 min | 5 min (10 modified) | 94% |

Slim CI is essential for any project with >20 models. Without it, CI becomes a bottleneck.

> **Reference:** [dbt Slim CI](https://docs.getdbt.com/docs/deploy/continuous-integration)

---

## 9. Deployment and Scaling

### Deployment Patterns

| Pattern | How | When |
|---------|-----|------|
| **Full build** | `dbt build` | First deployment, after major refactors |
| **Modified-only** | `dbt build --select state:modified+` | Standard CD after merge |
| **Tag-based** | `dbt build --select tag:hourly` | When different models have different schedules |
| **Exclude pattern** | `dbt build --exclude tag:heavy` | Skip expensive models during frequent runs |

### Scheduling Strategies

Not all models need to run at the same frequency:

```yaml
# dbt_project.yml
models:
  my_project:
    transient:
      +tags: ['schedule:hourly']
    bronze:
      +tags: ['schedule:hourly']
    silver:
      +tags: ['schedule:daily']
    gold:
      +tags: ['schedule:daily']
    gold_analytics:
      +tags: ['schedule:daily']
```

Then in your scheduler (Airflow, dbt Cloud, GitHub Actions cron):

```bash
# Every hour: only transient + bronze
dbt build --select tag:schedule:hourly

# Once a day: everything
dbt build
```

### Warehouse Sizing for dbt

| Operation | Warehouse Size | Why |
|-----------|---------------|-----|
| Local development | XS or S | Interactive queries, small data |
| CI builds | S or M | Limited data (cloned/sampled), fast feedback |
| Production daily build | M or L | Full data, all models |
| Full refresh | L or XL | Rebuilding large incremental tables |

**Use Snowflake multi-cluster warehouses** for CI if you have many concurrent PRs. Each PR gets its own CI build, and a multi-cluster warehouse auto-scales.

### Thread Configuration

dbt runs models in parallel up to `threads` count. More threads = more parallelism = faster builds (up to a point).

| Scenario | Threads | Why |
|----------|---------|-----|
| Development | 4 | Enough for local testing, doesn't overload dev warehouse |
| CI | 8 | Fast builds, CI warehouse is dedicated |
| Production | 8-16 | Maximize parallelism on prod warehouse |

**Warning:** More threads ≠ always faster. If your DAG is mostly sequential (linear chain), extra threads are wasted. Threads help when you have wide, parallel branches in your DAG.

### Monitoring Production

After deployment, monitor:

1. **Run duration** — track build time over time. If it's growing, find which models are getting slower.
2. **Row counts** — sudden drops/spikes indicate source issues.
3. **Test failures** — set up alerts (Slack, email) for `error` severity test failures.
4. **Source freshness** — run `dbt source freshness` before your build. If sources are stale, skip the build.

```bash
# Run source freshness first, fail fast
dbt source freshness && dbt build
```

### Artifacts

dbt generates artifacts after every run in the `target/` directory:

| File | Contains | Use For |
|------|----------|---------|
| `manifest.json` | Full project graph, compiled SQL | Slim CI state comparison, lineage tools |
| `run_results.json` | Execution results (timing, status) | Performance monitoring, alerting |
| `catalog.json` | Column-level metadata | Documentation, data catalog integration |
| `sources.json` | Source freshness results | Freshness monitoring |

**Always persist `manifest.json`** as a CI/CD artifact. It's required for Slim CI and `--defer`.

> **Reference:** [dbt Deployment](https://docs.getdbt.com/docs/deploy/deployments)

---

## 10. Snowflake-Specific Limitations

### dbt + Snowflake Adapter Limitations

| Limitation | Detail | Workaround |
|-----------|--------|-----------|
| **No `CREATE OR ALTER TABLE`** | dbt uses `CREATE OR REPLACE TABLE`, which drops and recreates. Grants, policies, and tags on the table are lost. | Re-apply grants via post-hooks or Snowflake `GRANT` statements in macros. |
| **No native dynamic tables** | dbt doesn't natively manage Snowflake Dynamic Tables. You can't set `materialized='dynamic_table'` out of the box. | Use DDLs outside dbt, or use the `dbt-snowflake` adapter's experimental dynamic table support (added in adapter v1.6+, but with limitations). |
| **Snapshot `check_cols` performance** | Using `check_cols='all'` on wide tables (100+ columns) generates massive MERGE statements. Slow and error-prone. | Use `strategy='timestamp'` with `updated_at` column instead. Much faster. |
| **Secure views not default** | dbt creates regular views. Snowflake Secure Views (which hide SQL definition from non-owners) require explicit config. | `{{ config(materialized='view', secure=true) }}` |
| **Transient tables** | Snowflake transient tables have limited Time Travel (0-1 day) and no Fail-safe. dbt supports this via config but it's opt-in. | `{{ config(transient='true') }}` — use for staging/transient zone. |
| **Copy grants** | `CREATE OR REPLACE TABLE` drops grants. dbt has a `copy_grants` config but it only works for views on some adapters. For tables, grants may still be lost. | Use `+copy_grants: true` in `dbt_project.yml`. Test in your environment. Or use post-hooks: `grant select on {{ this }} to role analyst`. |
| **Merge behavior with nulls** | Snowflake's MERGE treats NULL != NULL (SQL standard). If your `unique_key` column can be null, the merge won't match correctly. | Ensure `unique_key` columns are `NOT NULL`, or use `coalesce()` in your key. |
| **Large SQL compilation** | Very complex models with many macros can compile to SQL exceeding Snowflake's 1MB query size limit. Rare but happens with dynamic SQL generation. | Break the model into smaller pieces or reduce macro nesting. |

### Snowflake Features Not Manageable by dbt

These Snowflake objects must be managed outside dbt (via DDLs, Terraform, or SnowSQL):

| Object | Why Not dbt |
|--------|------------|
| **Databases** | dbt operates within a database, doesn't create them |
| **Warehouses** | Infrastructure, not data transformation |
| **Roles and users** | Access control, not data transformation |
| **Network policies** | Security config |
| **Resource monitors** | Cost management |
| **Shares** | Data sharing |
| **Stages** | External/internal stages for data loading |
| **File formats** | Data loading config |
| **Pipes (Snowpipe)** | Continuous ingestion |
| **Tasks** | Scheduled SQL (use dbt scheduling instead) |
| **Streams** | CDC capture (dbt has no native support) |
| **Row access policies** | Row-level security |
| **Masking policies** | Column-level security |
| **Tags** | Governance metadata |

**This is why this project has a `ddls/` folder** — to manage these objects as code alongside dbt.

### Snowflake Query Optimization for dbt

| Tip | Detail |
|-----|--------|
| **Avoid `ORDER BY` in models** | Snowflake is columnar — ordering is meaningless for storage. Only use in final BI-facing views if the BI tool requires it. |
| **Use `QUALIFY` instead of subqueries for dedup** | `QUALIFY ROW_NUMBER() OVER (...) = 1` is more efficient than wrapping in a CTE. Snowflake-specific syntax. |
| **Avoid `SELECT DISTINCT` on large tables** | Costs a full table scan + sort. Use `QUALIFY` or `GROUP BY` when possible. |
| **Leverage semi-structured data** | Use `VARIANT`, `OBJECT`, `ARRAY` columns with Snowflake's `:` notation. Avoid flattening into 50 columns if only 5 are used. |
| **Partition pruning** | For incremental models, always filter on the clustering key. Snowflake prunes micro-partitions based on this. |

> **Reference:** [dbt-snowflake adapter](https://docs.getdbt.com/docs/core/connect-data-platform/snowflake-setup)

---

## 11. dbt Ecosystem: Core, Cloud, and Fusion

### dbt Core (Open Source)

**What it is:** The open-source command-line tool. You install it with `pip install dbt-core dbt-snowflake`. It handles compilation, execution, testing — everything described in this guide.

**License:** Apache 2.0 (open source, free forever for the existing versions).

**Current status (as of early 2025):**
- dbt Labs has announced that **dbt Core will enter maintenance mode**. New features will go into dbt Cloud and dbt Fusion, not Core.
- Existing versions (1.x) will receive security patches but no major new features.
- The community can still fork and maintain it (it's open source), but official development focus has shifted.

**Impact for teams using Core:**
- Your current dbt Core projects will continue to work. Nothing breaks overnight.
- You won't get new features (microbatch improvements, advanced CI, etc.) unless you move to Cloud or Fusion.
- The `dbt-snowflake` adapter is maintained by dbt Labs — if Core is deprioritized, adapter updates may slow down.
- Community adapters (dbt-duckdb, dbt-bigquery, etc.) are independently maintained and may continue evolving.

### dbt Cloud

**What it is:** dbt Labs' managed SaaS platform. Includes a web IDE, job scheduler, CI/CD, documentation hosting, and semantic layer.

**Pricing:** Per-seat, with tiers (Developer, Team, Enterprise). Not free for organizations beyond 1 developer seat.

**Key features beyond Core:**
- Built-in scheduler (no need for Airflow/GitHub Actions for scheduling)
- Semantic Layer (metrics definitions queried by BI tools)
- IDE in browser (no local setup)
- Built-in CI with automatic Slim CI
- Environment management (no manual profile switching)

**When it makes sense:** Teams of 5+ data engineers who want managed infrastructure and don't want to maintain CI/CD pipelines, schedulers, and artifact storage themselves.

### dbt Fusion

**What it is:** dbt Labs' next-generation runtime, announced as the successor to dbt Core's execution engine. Written in Rust for performance. Designed to be significantly faster than Core's Python-based execution.

**Key changes:**
- **Not fully open source.** dbt Fusion is proprietary. The core compilation/execution engine is closed source, though the project definition format (models, YAML, macros) remains compatible.
- **Free for individual developers**, but organizations need a paid dbt Cloud license to use it in production.
- **Performance claims:** 10-100x faster compilation and parsing than dbt Core. Meaningful for large projects (1000+ models) where `dbt compile` alone takes minutes.

**Impact for this project:**
- **Your models, macros, YAML, and tests are compatible.** dbt Fusion reads the same project structure — you don't need to rewrite anything.
- **Your CI/CD pipelines need updating.** Instead of `pip install dbt-core`, you'd install the Fusion runtime. GitHub Actions workflows change.
- **Cost consideration.** If you're currently running dbt Core for free in CI/CD, moving to Fusion means paying for dbt Cloud licenses for your CI runners (organizational use).

### Decision Matrix

| Scenario | Recommendation |
|----------|---------------|
| Solo developer, learning dbt | dbt Core (free, full-featured) |
| Small team (2-5), budget-conscious | dbt Core + GitHub Actions CI/CD (this project's approach) |
| Medium team (5-15), want managed infra | dbt Cloud Team tier |
| Large team (15+), enterprise governance | dbt Cloud Enterprise |
| Need fastest possible compilation | dbt Fusion (requires Cloud license) |
| Want to avoid vendor lock-in | dbt Core (open source, community-maintained) |

### Practical Advice

1. **Don't panic about Core's future.** Your dbt Core 1.x projects will work for years. The SQL, YAML, and macros you write are the valuable part — not the runtime. They transfer to any future dbt runtime.

2. **Invest in the project, not the tool.** Good models, tests, documentation, and CI/CD are what matter. Whether you run them with Core, Cloud, or Fusion is a runtime decision you can change later.

3. **Keep your CI/CD independent.** This project uses GitHub Actions — your CI/CD is not locked to dbt Cloud. If you move to Fusion later, you only change the `pip install` step.

4. **Monitor the community.** dbt Core is Apache 2.0 licensed. If dbt Labs stops maintaining it, the community (or a fork) can continue. This has happened with other open-source projects.

5. **Evaluate dbt Cloud on ROI, not features.** The question isn't "does Cloud have more features?" (it does). The question is "does the time saved by Cloud justify the per-seat cost for my team?"

> **Reference:** [dbt Core](https://docs.getdbt.com/docs/core/about-core), [dbt Cloud](https://www.getdbt.com/product/dbt-cloud), [dbt Fusion announcement](https://www.getdbt.com/blog/dbt-fusion)

---

## Quick Reference Card

```
MATERIALIZATION       table → incremental → view → ephemeral
                      (most concrete)              (least concrete)

TESTING PRIORITY      PK (unique+not_null) → FK (relationships) → business rules → freshness

SELECTORS             model+ (downstream)  +model (upstream)  +model+ (full lineage)
                      state:modified+      tag:gold           path:models/gold/

COMMANDS              dbt build (always)   dbt compile (debug)   dbt docs generate (lineage)

ENVIRONMENTS          dev (isolated)  →  uat (shared test)  →  main (production)

INCREMENTAL SAFETY    is_incremental() guard  +  lookback window  +  merge unique_key
```

---

**Maintained by Anouar Zbaida | Crithink**
