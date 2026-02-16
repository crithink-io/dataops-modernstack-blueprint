# dbt-workflow

**Maintainer:** Anouar Zbaida | **Stack:** dbt + Snowflake + GitHub Actions

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
  - [5-Zone Medallion Architecture](#5-zone-medallion-architecture)
  - [Zone Responsibilities](#zone-responsibilities)
  - [Data Flow (DAG)](#data-flow-dag)
  - [Common Zone: \_DB\_UTILS](#common-zone-_db_utils)
- [Project Structure](#project-structure)
- [Models by Zone](#models-by-zone)
  - [Transient Zone](#transient-zone)
  - [Bronze Zone](#bronze-zone)
  - [Silver Zone](#silver-zone)
  - [Gold Zone](#gold-zone)
  - [Gold Analytics Zone](#gold-analytics-zone)
- [Reject Table Pattern](#reject-table-pattern)
- [Snapshots](#snapshots)
- [Macros](#macros)
- [DDLs (Snowflake Infrastructure)](#ddls-snowflake-infrastructure)
  - [DDL Folder Hierarchy](#ddl-folder-hierarchy)
  - [CREATE OR ALTER Pattern](#create-or-alter-pattern)
- [CI/CD Pipeline](#cicd-pipeline)
  - [dbt CI Workflow](#dbt-ci-workflow-dbt_ciyml)
  - [dbt CD Workflow](#dbt-cd-workflow-dbt_cdyml)
  - [dbt Teardown Workflow](#dbt-teardown-workflow-dbt_teardownyml)
  - [DDL CI Workflow](#ddl-ci-workflow-ddl_ciyml)
  - [DDL CD Workflow](#ddl-cd-workflow-ddl_cdyml)
  - [Branch Protection](#branch-protection)
- [Git Workflow](#git-workflow)
  - [Branch Strategy](#branch-strategy)
  - [Developer Flow](#developer-flow)
- [Stored Procedures](#stored-procedures)
- [Testing Strategy](#testing-strategy)
- [Developer Quick-Start](#developer-quick-start)
- [Environment Variables](#environment-variables)
- [Best Practices](#best-practices)

---

## Overview

This repository provides a **production-grade CI/CD template** for dbt projects on Snowflake, with a separate **DDLs folder** for managing Snowflake infrastructure objects. It implements a **5-zone medallion architecture** with multi-branch deployment, PR-isolated testing, and automated schema lifecycle management.

**Key Features:**
- **Dual-folder structure**: `dbt-project/` for dbt models + `ddls/` for Snowflake DDLs
- 5-zone data architecture (Transient → Bronze → Silver → Gold → Gold Analytics)
- Two-stage reject table pattern (technical + business)
- Multi-branch CI/CD (dev / uat / main → DEV / UAT / PROD)
- Path-based workflow triggers (dbt changes → dbt CI, DDL changes → DDL CI)
- DDL deployment with `CREATE OR ALTER` (preserves grants and privileges)
- PR-isolated schemas in `_DB_UTILS` database
- Data cloning with sampling and PII masking
- Slim CI with `state:modified+` and `--defer`
- SQLFluff linting enforced on BOTH dbt SQL and DDL SQL (pre-commit + CI)
- Branch protection: stale PRs must re-validate after new merges

---

## Architecture

### 5-Zone Medallion Architecture

```
┌──────────────────────────────────────────────────────────────────────────────────────────┐
│                              DATA ARCHITECTURE                                          │
│                                                                                          │
│  ┌───────────┐    ┌───────────┐    ┌───────────┐    ┌───────────┐    ┌──────────────┐   │
│  │           │    │           │    │           │    │           │    │              │   │
│  │ TRANSIENT │───>│  BRONZE   │───>│  SILVER   │───>│   GOLD    │───>│    GOLD      │   │
│  │   ZONE    │    │   ZONE    │    │   ZONE    │    │   ZONE    │    │  ANALYTICS   │   │
│  │           │    │           │    │           │    │           │    │              │   │
│  └─────┬─────┘    └───────────┘    └─────┬─────┘    └───────────┘    └──────────────┘   │
│        │                                 │                                               │
│        ▼                                 ▼                                               │
│  ┌───────────┐                     ┌───────────┐                                        │
│  │ TECHNICAL │                     │ BUSINESS  │                                        │
│  │ REJECTS   │                     │ REJECTS   │                                        │
│  └───────────┘                     └───────────┘                                        │
│                                                                                          │
│                    ┌────────────────────────────┐                                        │
│                    │   _DB_UTILS (Common Zone)  │                                        │
│                    │  CI schemas │ Stored procs  │                                        │
│                    └────────────────────────────┘                                        │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```

### Zone Responsibilities

| Zone | Schema | Materialization | Prefix | Purpose |
|------|--------|-----------------|--------|---------|
| **Transient** | `transient` | `table` | `trn_` | Truncate & reload. Technical validation. Tag `_is_valid`. |
| **Bronze** | `bronze` | `incremental` (append) | `brz_` | Append-only raw history. No transforms. Tag metadata. |
| **Silver** | `silver` | `table` / `ephemeral` | `slv_` | Dedup, standardize, normalize. Business validation. |
| **Gold** | `gold` | `table` | `dim_` / `fct_` | Business rules. Star schema (dims + facts). |
| **Gold Analytics** | `gold_analytics` | `table` | `agg_` | Pre-aggregated BI-ready models. |
| **Common** | `_DB_UTILS` | N/A | N/A | CI/PR schemas, stored procedures, metadata. |

### Data Flow (DAG)

```
                TRANSIENT          BRONZE             SILVER              GOLD           GOLD ANALYTICS
                ─────────          ──────             ──────              ────           ──────────────

Seeds/Fivetran ──> trn_customers ──> brz_customers ──> slv_customers ──> dim_customers ──> agg_sales_by_customer
              trn_customers_rejects                slv_customers_rejects     │
                                                                             │
Seeds/Fivetran ──> trn_orders ────> brz_orders ────> slv_orders ──────> fct_orders ──────> agg_daily_revenue
              trn_orders_rejects                  slv_orders_rejects    │
                                                                        │
Seeds/Fivetran ──> trn_order_items > brz_order_items > slv_order_items ─────┘
              trn_order_items_rejects              slv_order_items_rejects

Seeds/Fivetran ──> trn_products ──> brz_products ──> slv_products ──> dim_products ──> agg_sales_by_product
              trn_products_rejects               slv_products_rejects

                                                slv_customers ──> snap_customers (SCD Type 2)
```

### Common Zone: \_DB\_UTILS

The `_DB_UTILS` database serves as the **Common Zone** and exists because:

1. **Permission isolation**: Developers may not have `CREATE SCHEMA` on application databases
2. **PR schema isolation**: Each PR gets its own schema (`PR_<number>__<sha7>`) to prevent conflicts
3. **Shared utilities**: Stored procedures for cloning, sampling, and metadata operations
4. **Clean separation**: CI/CD artifacts don't pollute production databases

**Schema routing** is handled by the `generate_schema_name` macro:

```
┌──────────────────────────────────────────────────────────────┐
│                   Schema Routing Logic                        │
│                                                              │
│  target.name == 'ci'                                         │
│    └──> All models → _DB_UTILS.PR_<number>__<sha7>          │
│         (flat schema, all zones together)                     │
│                                                              │
│  target.name in ('dev', 'uat', 'prod')                       │
│    └──> Models → APP_DB.<zone_schema>                        │
│         e.g. APP_DB.TRANSIENT, APP_DB.BRONZE, etc.           │
└──────────────────────────────────────────────────────────────┘
```

---

## Project Structure

```
dbt-workflow/                                  # Repo root
│
├── dbt-project/                               # ── dbt models & config ──
│   ├── dbt_project.yml                        # Project configuration
│   ├── profiles.yml                           # Connection profiles (env vars)
│   ├── packages.yml                           # dbt packages
│   ├── dbt-requirements.txt                   # Python/dbt dependencies
│   ├── .sqlfluff                              # SQL linting (jinja templater)
│   ├── models/
│   │   ├── transient/                         # Zone 1: Landing & validation
│   │   │   ├── _transient__sources.yml
│   │   │   ├── _transient__models.yml
│   │   │   ├── trn_*.sql                      # Truncate & reload models
│   │   │   └── trn_*_rejects.sql              # Technical reject tables
│   │   ├── bronze/                            # Zone 2: Raw history (append-only)
│   │   ├── silver/                            # Zone 3: Cleaned & standardized
│   │   │   └── _validated/                    # Ephemeral validation layer (DRY)
│   │   ├── gold/                              # Zone 4: Star schema (dim_*, fct_*)
│   │   └── gold_analytics/                    # Zone 5: BI-ready (agg_*)
│   ├── macros/
│   │   ├── generate_schema_name.sql           # Environment-aware schema routing
│   │   ├── clone_for_ci.sql                   # Calls CLONE_FOR_CI stored procedure
│   │   ├── drop_pr_schemas.sql                # Drops PR schemas (teardown)
│   │   ├── tag_columns.sql                    # Reusable metadata tagging
│   │   └── validate_row_counts.sql            # Row count comparison
│   ├── snapshots/
│   │   └── snap_customers.sql                 # SCD Type 2 customer tracking
│   ├── seeds/                                 # Raw CSV data (dev only)
│   ├── tests/                                 # Singular tests
│   └── analyses/                              # Ad-hoc SQL
│
├── ddls/                                      # ── Snowflake DDLs ──
│   ├── .sqlfluff                              # SQL linting (raw templater)
│   ├── _account/                              # Account-level objects
│   │   ├── databases/
│   │   │   ├── APP_DB.sql                     # CREATE OR ALTER DATABASE
│   │   │   └── _DB_UTILS.sql
│   │   └── warehouses/
│   │       └── ANALYTICS_WH.sql               # CREATE OR ALTER WAREHOUSE
│   ├── _DB_UTILS/                             # Database: _DB_UTILS
│   │   ├── _schemas/
│   │   │   └── PUBLIC.sql                     # CREATE OR ALTER SCHEMA
│   │   └── PUBLIC/
│   │       └── procedures/
│   │           └── clone_for_ci.sql           # CREATE OR REPLACE PROCEDURE
│   └── APP_DB/                                # Database: APP_DB
│       ├── _schemas/
│       │   ├── RAW.sql, TRANSIENT.sql         # CREATE OR ALTER SCHEMA
│       │   ├── BRONZE.sql, SILVER.sql
│       │   ├── GOLD.sql, GOLD_ANALYTICS.sql
│       └── RAW/                               # Schema: RAW (not managed by dbt)
│           ├── tables/                        # CREATE OR ALTER TABLE
│           ├── views/                         # (placeholder)
│           ├── stages/                        # (placeholder)
│           ├── file_formats/                  # (placeholder)
│           └── functions/                     # (placeholder)
│
├── .github/
│   ├── workflows/
│   │   ├── dbt_ci.yml                         # dbt CI: lint + build on PR
│   │   ├── dbt_cd.yml                         # dbt CD: deploy on merge
│   │   ├── dbt_teardown.yml                   # dbt: cleanup PR schemas
│   │   ├── ddl_ci.yml                         # DDL CI: lint + validate on PR
│   │   └── ddl_cd.yml                         # DDL CD: deploy on merge
│   └── branch-protection.md                   # GitHub branch protection setup
│
├── scripts/
│   └── init_project.py                        # Project initializer (customize names)
│
├── .pre-commit-config.yaml                    # Pre-commit hooks (both folders)
├── .gitignore
├── README.md
├── TEMPLATE_GUIDE.md
├── DBT_BEST_PRACTICES.md                      # dbt patterns, anti-patterns, limitations
└── ANALYSIS.md
```

---

## Models by Zone

### Transient Zone

**Purpose:** First landing point for data in dbt. Truncate and reload each run. Perform technical validation.

**Pattern:**
```
┌──────────────┐     ┌──────────────────┐     ┌───────────────┐
│  Source Data  │────>│  trn_<entity>    │────>│  Valid rows    │──> Bronze
│ (seed/Fivetran)     │  + _is_valid     │     │  (_is_valid=T) │
└──────────────┘     │  + _loaded_at    │     └───────────────┘
                     │  + _batch_id     │
                     └────────┬─────────┘     ┌───────────────┐
                              └──────────────>│  trn_*_rejects │
                                              │  (invalid rows)│
                                              └───────────────┘
```

**Conditional source** — uses seeds in dev, Fivetran tables in uat/prod:

```sql
{% if target.name == 'dev' %}
    select * from {{ ref('raw_customers') }}
{% else %}
    select * from {{ source('fivetran_raw', 'customers') }}
{% endif %}
```

**Metadata columns added:** `_is_valid`, `_loaded_at`, `_batch_id`

### Bronze Zone

**Purpose:** Append-only historical storage. No transformations. Tag with metadata.

- **Materialization:** Incremental (append strategy — never deletes)
- **Source:** Valid rows from transient (`_is_valid = true`)
- **Tagging:** `_source_system`, `_domain`, `_sensitivity_tag`
- **Surrogate key:** `_bronze_sk` (entity PK + `_batch_id`)

### Silver Zone

**Purpose:** Deduplication, naming standardization, business validation.

**3-Layer Pattern:**
```
┌─────────────────────────────┐
│  _validated/ (EPHEMERAL)    │     ← Shared validation logic (DRY)
│  slv_*_validated.sql        │
│  - dedup via row_number()   │
│  - standardize column names │
│  - business rule validation │
│  - adds _is_valid flag      │
└──────────┬──────────────────┘
           │
     ┌─────┴─────┐
     │           │
     ▼           ▼
┌─────────┐  ┌──────────────┐
│ slv_*   │  │ slv_*_rejects│    ← Business reject table
│ (clean) │  │ (incremental)│
│ _is_valid│  │ _is_valid    │
│ = true  │  │ = false      │
└─────────┘  └──────────────┘
```

The `_validated/` subfolder contains **ephemeral models** (no table created in Snowflake). Both the clean model and reject model reference the same validated model. This prevents duplicating dedup/validation logic.

### Gold Zone

**Purpose:** Business rules, star schema modeling.

| Model | Type | Description |
|-------|------|-------------|
| `dim_customers` | Dimension | Customer attributes + aggregated order metrics (total orders, spend, tier) |
| `dim_products` | Dimension | Product attributes + sales metrics (units sold, revenue, category) |
| `fct_orders` | Fact | Foreign keys + measures only. No denormalized attributes. |

**Star schema principle:** `fct_orders` contains only:
- Foreign keys: `customer_id`, `product_id`, `order_id`
- Measures: `quantity`, `unit_price`, `total_price`, `discount_amount`, `order_total`
- Degenerate dims: `order_date`, `status`, `payment_method`

### Gold Analytics Zone

**Purpose:** Pre-aggregated models for BI tools. Dedicated `gold_analytics` schema.

| Model | Description |
|-------|-------------|
| `agg_sales_by_customer` | Customer-level sales metrics |
| `agg_sales_by_product` | Product-level performance metrics |
| `agg_daily_revenue` | Daily revenue trends |

---

## Reject Table Pattern

Data quality is enforced at two stages:

```
┌────────────┐                                    ┌────────────┐
│  STAGE 1   │                                    │  STAGE 2   │
│  Technical │                                    │  Business  │
│  (Transient)│                                   │  (Silver)  │
├────────────┤                                    ├────────────┤
│ NULL PKs   │                                    │ Invalid    │
│ NULL req'd │                                    │  email fmt │
│  columns   │                                    │ Orphaned   │
│            │                                    │  FKs       │
│ Stored in  │                                    │ Bad ranges │
│ trn_*_     │                                    │            │
│  rejects   │                                    │ Stored in  │
│            │                                    │ slv_*_     │
│ (incr.)    │                                    │  rejects   │
└────────────┘                                    └────────────┘
```

**Technical rejects (transient):** Records with NULL primary keys or required fields. Caught before data enters the pipeline.

**Business rejects (silver):** Records that pass technical checks but violate business rules (invalid email format, orphaned foreign keys, out-of-range values). Caught after standardization.

Both reject tables are **incremental** (append-only) to maintain a full history of rejected records for investigation.

---

## Snapshots

`snap_customers` — SCD Type 2 snapshot tracking changes to customer data over time.

- **Source:** `slv_customers` (silver clean model)
- **Target schema:** `bronze`
- **Strategy:** `timestamp` on `updated_at`
- **Tracks:** `dbt_valid_from`, `dbt_valid_to` for historical queries

---

## Macros

| Macro | File | Purpose |
|-------|------|---------|
| `generate_schema_name` | `dbt-project/macros/generate_schema_name.sql` | Routes models to correct schema based on target (CI → flat PR schema, dev/uat/prod → zone schema) |
| `clone_for_ci` | `dbt-project/macros/clone_for_ci.sql` | Calls `_DB_UTILS.PUBLIC.CLONE_FOR_CI` stored procedure to clone and sample data for CI |
| `drop_pr_schemas` | `dbt-project/macros/drop_pr_schemas.sql` | Drops PR-specific schemas from `_DB_UTILS` during teardown |
| `tag_columns` | `dbt-project/macros/tag_columns.sql` | Adds reusable metadata columns (source_system, domain, sensitivity) |
| `validate_row_counts` | `dbt-project/macros/validate_row_counts.sql` | Compares row counts between source and target relations |

---

## DDLs (Snowflake Infrastructure)

The `ddls/` folder manages **all Snowflake objects not created by dbt** — from databases and warehouses down to tables, views, and procedures. Each `.sql` file defines exactly one Snowflake object.

### DDL Folder Hierarchy

The folder structure mirrors Snowflake's object hierarchy:

```
ddls/
├── _account/              ← Account-level (no parent database)
│   ├── databases/         ← CREATE OR ALTER DATABASE
│   └── warehouses/        ← CREATE OR ALTER WAREHOUSE
│
├── <DATABASE>/            ← One folder per database
│   ├── _schemas/          ← CREATE OR ALTER SCHEMA
│   └── <SCHEMA>/          ← One folder per schema
│       ├── tables/        ← CREATE OR ALTER TABLE
│       ├── views/         ← CREATE OR ALTER VIEW
│       ├── functions/     ← CREATE OR REPLACE FUNCTION
│       ├── procedures/    ← CREATE OR REPLACE PROCEDURE
│       ├── stages/        ← CREATE STAGE
│       └── file_formats/  ← CREATE FILE FORMAT
```

### CREATE OR ALTER Pattern

Most DDLs use `CREATE OR ALTER` to **preserve existing grants and privileges**:

```sql
-- ddls/_account/databases/APP_DB.sql
create or alter database APP_DB
    data_retention_time_in_days = 14
    comment = 'Application database for dbt medallion pipeline';

-- ddls/APP_DB/_schemas/RAW.sql
create or alter schema APP_DB.RAW
    data_retention_time_in_days = 7
    comment = 'Raw landing zone for Fivetran data';

-- ddls/APP_DB/RAW/tables/customers.sql
create or alter table APP_DB.RAW.CUSTOMERS (
    customer_id     integer         not null,
    first_name      varchar(100),
    ...
);
```

**Exception:** Procedures and functions use `CREATE OR REPLACE` (Snowflake doesn't support `CREATE OR ALTER` for these object types).

---

## CI/CD Pipeline

### Overview

The CI/CD pipeline is **path-based** — dbt workflows trigger only on `dbt-project/` changes, DDL workflows trigger only on `ddls/` changes.

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          CI/CD FLOW                                      │
│                                                                          │
│  Developer                                                               │
│     │                                                                    │
│     ├── modifies dbt-project/ ─────────────────────────────────────┐     │
│     │                                                               │     │
│     │   ┌──────────────┐      ┌──────────────┐      ┌───────────┐  │     │
│     │   │  dbt_ci.yml  │─────>│  dbt_cd.yml  │      │ teardown  │  │     │
│     │   │              │      │              │      │ .yml      │  │     │
│     │   │ 1. Lint SQL  │      │ 1. Build     │      │           │  │     │
│     │   │ 2. Clone data│      │    modified+  │      │ Drop PR   │  │     │
│     │   │ 3. Build     │      │ 2. Upload    │      │ schema    │  │     │
│     │   │    modified+  │      │    manifest   │      │           │  │     │
│     │   └──────────────┘      └──────────────┘      └───────────┘  │     │
│     │                                                               │     │
│     ├── modifies ddls/ ────────────────────────────────────────┐    │     │
│     │                                                           │    │     │
│     │   ┌──────────────┐      ┌──────────────┐                 │    │     │
│     │   │  ddl_ci.yml  │─────>│  ddl_cd.yml  │                 │    │     │
│     │   │              │      │              │                 │    │     │
│     │   │ 1. Lint SQL  │      │ 1. Detect    │                 │    │     │
│     │   │ 2. Validate  │      │    changed   │                 │    │     │
│     │   │    syntax    │      │ 2. Deploy    │                 │    │     │
│     │   │              │      │    in order  │                 │    │     │
│     │   └──────────────┘      └──────────────┘                 │    │     │
│     │                                                           │    │     │
│     └── modifies both ─── ALL workflows trigger ───────────────┘    │     │
└──────────────────────────────────────────────────────────────────────────┘
```

### dbt CI Workflow (`dbt_ci.yml`)

**Trigger:** Pull request to `main`, `uat`, or `dev` — only when `dbt-project/**` files change

**Two jobs run in sequence:**

**Job 1 — `dbt_lint` (blocks merge on failure):**
1. **SQLFluff lint** — validates all SQL files against `dbt-project/.sqlfluff`
2. **YAML validation** — checks all `.yml` files for syntax errors

**Job 2 — `dbt_build` (runs only if lint passes):**
1. **Detect environment** from PR base branch:
   - `main` → prod (sample: 0%)
   - `uat` → uat (sample: 0%)
   - `dev` → dev (sample: 10%)
2. **Create PR schema** in `_DB_UTILS`: `PR_<number>__<sha7>`
3. **Clone data** via `CLONE_FOR_CI` stored procedure (sample for dev, full for uat/prod)
4. **Download per-env manifest** artifact (if exists, `continue-on-error: true`)
5. **dbt build** with `state:modified+` and `--defer` (slim CI)
6. **Fallback:** Full build if no manifest exists (first run)

**Key features:**
- All dbt commands run from `dbt-project/` working directory
- SQLFluff lint gate — PRs cannot merge if SQL doesn't comply with linting rules
- Concurrency group prevents parallel runs on same PR
- Pip caching for faster builds
- Masked-data role for PII protection during cloning

### dbt CD Workflow (`dbt_cd.yml`)

**Trigger:** Push (merge) to `main`, `uat`, or `dev` — only when `dbt-project/**` files change

**Steps:**
1. **Detect environment** from branch name
2. **Download per-env manifest** (`dbt-manifest-dev`, `-uat`, `-prod`)
3. **dbt build** with `state:modified+` (deploy only changed models)
4. **Upload new manifest** artifact (14-day retention, `overwrite: true`)

### dbt Teardown Workflow (`dbt_teardown.yml`)

**Trigger:** PR closed (merged or abandoned) to `main`, `uat`, or `dev` — **always runs** (no path filter)

**Steps:**
1. Reconstruct PR schema name: `PR_<number>__<sha7>`
2. `dbt run-operation drop_pr_schemas` — CASCADE drops entire PR schema from `_DB_UTILS`

### DDL CI Workflow (`ddl_ci.yml`)

**Trigger:** Pull request to `main`, `uat`, or `dev` — only when `ddls/**` files change

**Two jobs run in sequence:**

**Job 1 — `ddl_lint`:** SQLFluff lint on changed SQL files in `ddls/` using `ddls/.sqlfluff` (raw templater)

**Job 2 — `ddl_validate`:** Dry-run syntax validation of changed DDL files against Snowflake via SnowSQL

### DDL CD Workflow (`ddl_cd.yml`)

**Trigger:** Push (merge) to `main`, `uat`, or `dev` — only when `ddls/**` files change

**Steps:**
1. Detect changed DDL files via `git diff`
2. Determine target environment from branch
3. Sort files by **deployment priority** (databases → warehouses → schemas → file_formats → stages → tables → views → functions → procedures)
4. Execute each file against Snowflake via SnowSQL

### Branch Protection

Stale PRs are automatically blocked from merging. See [.github/branch-protection.md](.github/branch-protection.md) for full setup instructions.

**Key setting:** "Require branches to be up to date before merging" — when PR2 merges to `main`, any previously-validated PR1 must update from `main` and re-pass CI before merging.

**Required status checks:** `dbt_lint`, `dbt_build`, `ddl_lint`, `ddl_validate`

---

## Git Workflow

### Branching Strategy: Feature Promotion

This project uses **feature promotion**, not branch promotion. Each feature branch is merged independently to each environment — you never promote `dev → uat → main` as a whole.

**Why?** Branch promotion (`dev → uat → main`) forces you to deploy everything together. If user A and user B both merge to `uat`, a PR from `uat → main` carries both changes — even if only A is validated by the business. Feature promotion solves this: each feature flows independently.

```
┌──────────────────────────────────────────────────────────────────────────┐
│                     FEATURE PROMOTION STRATEGY                          │
│                                                                         │
│  main ───────────────────────────────────────── ← PROD (source of truth)│
│    │                                                                    │
│    ├── feature/X (user A)                                               │
│    │     ├── PR → dev   (developer testing)                             │
│    │     ├── PR → uat   (business validation)                           │
│    │     └── PR → main  (production, after validation) ✅               │
│    │                                                                    │
│    └── feature/Y (user B)                                               │
│          ├── PR → dev   (developer testing)                             │
│          ├── PR → uat   (business validation)  ⏳ waiting...            │
│          └── PR → main  (blocked until validated)                       │
│                                                                         │
│  dev and uat are TESTING environments, not promotion steps.             │
│  Features merge to each target independently.                           │
│  main is always clean — only validated code lands here.                 │
└──────────────────────────────────────────────────────────────────────────┘
```

### Key Principles

| Principle | Detail |
|-----------|--------|
| **Branch from `main`** | Every feature branch starts from `main`, not from `dev` or `uat`. |
| **`main` = prod** | `main` is the source of truth. Only validated features are merged here. |
| **`dev` / `uat` are ephemeral** | They accumulate changes for testing. They can be reset to `main` periodically. |
| **One feature = one deployable unit** | If something needs independent business validation, it gets its own branch and PR. |
| **No cherry-picking** | Because features are merged independently, you never need to cherry-pick commits. |

### Developer Flow

| Step | Action | What Happens |
|------|--------|--------------|
| 1 | `git checkout main && git checkout -b feature/add-model` | Create feature branch **from main** |
| 2 | Develop & test locally with `dbt build --target dev` | Models run against Snowflake DEV |
| 3 | `git push -u origin feature/add-model` | Push feature branch to remote |
| 4 | Open PR: `feature/add-model → dev` | CI triggers: clone 10% sample, lint, slim build |
| 5 | Code review + CI passes → merge to `dev` | CD deploys to DEV. Teardown cleans PR schema. |
| 6 | Open PR: `feature/add-model → uat` | CI triggers: full clone, lint, slim build |
| 7 | Business validates in UAT → merge to `uat` | CD deploys to UAT. Teardown cleans PR schema. |
| 8 | Open PR: `feature/add-model → main` | CI triggers: full clone, lint, slim build |
| 9 | Final review → merge to `main` | CD deploys to PROD. Feature is live. |

**Branch naming convention:** `feature/<desc>`, `fix/<desc>`, `refactor/<desc>`

### Release Management

A "release" is simply the set of feature PRs merged to `main` in a given cycle:

```
Release v2.3:
  ✅ PR #42 — feature/customer-update     (validated → merged to main)
  ✅ PR #45 — feature/product-categories  (validated → merged to main)
  ⏳ PR #47 — feature/revenue-fix         (still in UAT → NOT in main)
```

You have full control over what goes to production. No feature reaches `main` without passing through validation.

### Resetting dev / uat

Because `dev` and `uat` accumulate changes from multiple features, they can diverge over time. Periodically reset them to match production:

```bash
# Reset uat to match prod (after a release cycle)
git checkout uat && git reset --hard main && git push --force origin uat

# Reset dev to match prod
git checkout dev && git reset --hard main && git push --force origin dev
```

This is safe because `dev` and `uat` are testing environments — `main` is the source of truth.

---

## Stored Procedures

### `_DB_UTILS.PUBLIC.CLONE_FOR_CI`

Located at `ddls/_DB_UTILS/PUBLIC/procedures/clone_for_ci.sql`. Deployed automatically via `ddl_cd.yml` when merged, or manually via SnowSQL.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `SOURCE_DB` | VARCHAR | Source database (e.g. `APP_DB_DEV`) |
| `SCHEMA_LIST` | VARCHAR | Comma-separated schemas (e.g. `TRANSIENT,BRONZE,SILVER,GOLD,GOLD_ANALYTICS`) |
| `TARGET_SCHEMA` | VARCHAR | PR schema name (e.g. `PR_42__A1B2C3D`) |
| `ENV_TYPE` | VARCHAR | Environment: `dev`, `uat`, or `prod` |
| `SAMPLE_PCT` | NUMBER | 0 = full zero-copy clone, >0 = CTAS with SAMPLE(n) |
| `ROLE_NAME` | VARCHAR | Masked-data role for PII protection |

**Clone strategy by environment:**

| Environment | PR Target | Sample | Clone Type | PII |
|-------------|-----------|--------|------------|-----|
| dev | `dev` branch | 10% | CTAS with SAMPLE | Masked |
| uat | `uat` branch | 0% (full) | Zero-copy CLONE | Masked |
| prod | `main` branch | 0% (full) | Zero-copy CLONE | Masked |

---

## Testing Strategy

Tests are defined per zone in `_<zone>__models.yml` files.

| Layer | Test Types | Zone |
|-------|-----------|------|
| **Base** | `not_null`, `unique` on PKs | All zones |
| **Integrity** | `relationships` between models | Silver, Gold |
| **Business** | `accepted_values` for enums | Silver, Gold |
| **Quality** | Reject tables, row counts | Transient, Silver |
| **SCD** | Snapshot tracking | Bronze |

**CI testing flow:**
1. PR opened → SQLFluff lint validates all SQL files
2. Lint passes → CI clones data to PR schema
3. `dbt build` runs models + tests on `state:modified+`
4. All lint checks and tests must pass before merge is allowed
5. After merge → CD deploys to target environment

---

## Developer Quick-Start

### Starting a New Project from This Template

```bash
# 1. Clone the template
git clone <repo-url> my-new-project && cd my-new-project

# 2. Run the init script to customize project name, database names, author, etc.
python scripts/init_project.py

# 3. Continue with setup below...
```

The init script prompts for project name, author, Snowflake database names, and warehouse name, then replaces all template values across the codebase (including renaming DDL directories). It also offers to update the Git remote origin to your new repo and push an initial commit.

### Setup

```bash
# 1. Create virtual environment
python -m venv venv && source venv/bin/activate

# 2. Install dbt + linting tools
pip install -r dbt-project/dbt-requirements.txt

# 3. Set up pre-commit hooks
pre-commit install

# 5. Set environment variables (see section below)
export SNOWFLAKE_ACCOUNT=...
export SNOWFLAKE_USER=...
export SNOWFLAKE_PASSWORD=...
export SNOWFLAKE_ROLE=...
export SNOWFLAKE_WAREHOUSE=...
export SNOWFLAKE_DATABASE=...

# 6. Navigate to dbt project and verify connection
cd dbt-project
dbt debug --target dev

# 7. Install packages
dbt deps

# 8. Load seed data (dev only)
dbt seed

# 9. Build everything (seed + run + test + snapshot)
dbt build

# 10. Lint dbt SQL files
sqlfluff lint models/ macros/

# 11. Lint DDL SQL files (from repo root)
cd ..
sqlfluff lint ddls/ --config ddls/.sqlfluff

# 12. Generate docs
cd dbt-project
dbt docs generate && dbt docs serve

# 13. Create feature branch and start developing
git checkout -b feature/my-change dev
# ... make changes ...
git push -u origin feature/my-change
# Open PR to dev → CI runs automatically
```

---

## Environment Variables

### Required for all targets

| Variable | Description |
|----------|-------------|
| `SNOWFLAKE_ACCOUNT` | Snowflake account identifier |
| `SNOWFLAKE_USER` | Snowflake username |
| `SNOWFLAKE_PASSWORD` | Snowflake password |
| `SNOWFLAKE_ROLE` | Default role |
| `SNOWFLAKE_WAREHOUSE` | Warehouse name |
| `SNOWFLAKE_DATABASE` | Application database |

### CI-specific (GitHub Secrets)

| Variable | Description |
|----------|-------------|
| `SNOWFLAKE_CI_ROLE` | CI role (defaults to `SNOWFLAKE_ROLE`) |
| `SNOWFLAKE_CI_DATABASE` | CI database (defaults to `_DB_UTILS`) |

---

## Best Practices

### Modeling
- Zone-specific prefixes: `trn_`, `brz_`, `slv_`, `dim_`/`fct_`, `agg_`
- Explicit column selection (no `SELECT *`)
- CTE-based SQL patterns
- Star schema in gold (FKs + measures only in facts)
- DRY via ephemeral validated models in silver
- Conditional source (seed vs Fivetran) via Jinja

### CI/CD
- **Path-based triggers** — dbt workflows fire only on `dbt-project/` changes, DDL workflows only on `ddls/`
- Slim CI with `state:modified+` and `--defer`
- **SQLFluff lint gate** — PRs blocked if SQL doesn't pass linting (both dbt and DDL)
- PR-isolated schemas in `_DB_UTILS` (not application database)
- Per-environment manifest artifacts (`dbt-manifest-dev`, `-uat`, `-prod`)
- DDL deployment in dependency order (databases → schemas → tables → ...)
- Concurrency groups prevent parallel runs on same PR/branch
- Graceful first-run handling (`continue-on-error: true`)
- **Stale PR protection** — branch protection requires PRs to be up to date before merging

### DDLs
- `CREATE OR ALTER` to preserve grants and privileges
- One `.sql` file per Snowflake object, fully qualified names
- Folder hierarchy mirrors Snowflake's object hierarchy
- Separate `.sqlfluff` config with `raw` templater (no Jinja)

### Data Quality
- Two-stage reject pattern (technical in transient, business in silver)
- Schema tests on all primary/foreign keys
- `accepted_values` for enumerated fields
- SCD Type 2 snapshot for change tracking
- Metadata columns (`_loaded_at`, `_batch_id`, `_source_system`, etc.)

### Code Quality
- **Pre-commit hooks** enforce SQLFluff lint on BOTH `dbt-project/` and `ddls/` SQL files
- **CI lint jobs** catch issues even if pre-commit is bypassed — blocks merge on failure
- Two SQLFluff configs: `jinja` templater for dbt, `raw` templater for DDLs
- SQLFluff configured for Snowflake dialect (lowercase keywords, leading commas, explicit aliases)

### Configuration
- `generate_schema_name` macro for environment-aware routing
- Zone-level tagging via `dbt_project.yml` (`+tags: ['zone:*']`)
- All credentials externalized via environment variables
- Separate YAML per zone for test definitions

---

**Maintained by Anouar Zbaida | Crithink**
