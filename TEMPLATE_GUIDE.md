# Using This Repo as a dbt + Snowflake Template

**Maintainer:** Anouar Zbaida

This project is intended as a **best-practice template** for dbt on Snowflake with CI/CD and DDL management. Use it to start new projects and stay independent.

---

## What's Included (Scenarios Covered)

| Scenario | Where | Notes |
|----------|--------|------|
| **Dual-folder structure** | `dbt-project/`, `ddls/` | dbt models in one folder, Snowflake DDLs in another. Path-based CI/CD. |
| **5-zone medallion architecture** | `dbt-project/models/transient/`, `bronze/`, `silver/`, `gold/`, `gold_analytics/` | Transient → Bronze → Silver → Gold → Gold Analytics |
| **Landing from seeds (dev)** | `dbt-project/models/transient/trn_*.sql` | `ref('raw_*')` in dev; seeds for demos and local development. |
| **Landing from Snowflake sources (uat/prod)** | `dbt-project/models/transient/_transient__sources.yml` | `source('fivetran_raw', '...')` when data lives in Snowflake (synced by Fivetran). |
| **Two-stage reject pattern** | `dbt-project/models/transient/trn_*_rejects.sql`, `dbt-project/models/silver/slv_*_rejects.sql` | Technical rejects (transient) + business rejects (silver). |
| **Ephemeral validation (DRY)** | `dbt-project/models/silver/_validated/slv_*_validated.sql` | Shared validation logic consumed by clean + reject models. |
| **Dimensions & facts (star schema)** | `dbt-project/models/gold/` | `dim_*`, `fct_*` with docs and schema tests. |
| **Pre-aggregated analytics** | `dbt-project/models/gold_analytics/` | `agg_*` BI-ready models. |
| **SCD Type 2 (snapshots)** | `dbt-project/snapshots/snap_customers.sql` | Pattern for slowly changing dimensions. |
| **Schema tests** | `dbt-project/models/**/_*__models.yml` | unique, not_null, relationships, accepted_values per zone. |
| **Singular tests** | `dbt-project/tests/fct_orders_grain.sql` | Example grain test; add more under `tests/`. |
| **Custom macros** | `dbt-project/macros/` | Schema routing, PR teardown, metadata tagging, row count validation. |
| **Snowflake DDLs** | `ddls/` | Databases, schemas, warehouses, tables, procedures — all as `CREATE OR ALTER`. |
| **Multi-branch CI/CD** | `.github/workflows/dbt_ci.yml`, `dbt_cd.yml`, `dbt_teardown.yml`, `ddl_ci.yml`, `ddl_cd.yml` | Path-based triggers, PR schema isolation, slim CI, DDL deployment. |
| **Data cloning with sampling** | `dbt-project/macros/clone_for_ci.sql`, `ddls/_DB_UTILS/PUBLIC/procedures/clone_for_ci.sql` | Zero-copy clone (uat/prod) or sampled CTAS (dev) with PII masking. |
| **SQL linting** | `dbt-project/.sqlfluff`, `ddls/.sqlfluff`, `.pre-commit-config.yaml` | Dual SQLFluff configs — jinja for dbt, raw for DDLs. Pre-commit + CI enforcement. |
| **Feature promotion Git workflow** | README.md § Git Workflow | Branch from `main`, PR to each env independently. Selective releases, no cherry-picking. |
| **Branch protection** | `.github/branch-protection.md` | Stale PR protection, required status checks documentation. |
| **Analyses** | `dbt-project/analyses/` | Placeholder for ad-hoc SQL (e.g. `dbt compile` then run in Snowflake). |

---

## Quick Start (New Project From This Template)

1. **Clone or create repo from this template**
   ```bash
   git clone <this-repo> my-new-dbt-project && cd my-new-dbt-project
   ```

2. **Run the init script** to customize project name, databases, author, etc.
   ```bash
   python scripts/init_project.py
   ```
   This replaces all template values (project name, database names, warehouse, author) across the entire codebase, renames DDL directories, and optionally updates the Git remote origin to your new repo with an initial commit + push.

3. **Set Snowflake credentials (env vars)**
   - Required: `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`, `SNOWFLAKE_PASSWORD`, `SNOWFLAKE_ROLE`, `SNOWFLAKE_WAREHOUSE`, `SNOWFLAKE_DATABASE`
   - Per-environment (optional): `SNOWFLAKE_DATABASE_DEV`, `SNOWFLAKE_DATABASE_UAT`, `SNOWFLAKE_DATABASE_PROD`
   - For CI: add the same vars as GitHub repo Secrets, plus `SNOWFLAKE_CI_DATABASE` and `SNOWFLAKE_CI_ROLE`.

4. **Set up Python environment**
   ```bash
   python -m venv venv && source venv/bin/activate
   pip install -r dbt-project/dbt-requirements.txt
   ```

5. **Set up pre-commit hooks**
   ```bash
   pre-commit install
   ```

6. **Install and run dbt**
   ```bash
   cd dbt-project
   dbt deps
   dbt seed
   dbt build
   ```

7. **Optional: dbt docs**
   ```bash
   dbt docs generate && dbt docs serve
   ```

---

## When to Use What

- **Seeds:** Small, versioned reference data (CSV in repo). Use `ref('raw_*')` in transient models. Ideal for dev/demo.
- **Sources:** Raw data already in Snowflake (synced by Fivetran). Define in `_transient__sources.yml`, use `source('fivetran_raw', 'customers')` in transient models. Used in uat/prod.
- **Snapshots:** When you need history (SCD Type 2). Copy `dbt-project/snapshots/snap_customers.sql` and point to your source.
- **Incremental:** Bronze zone uses append-only incremental. Reject tables in transient and silver are also incremental to preserve history.
- **DDLs:** Any Snowflake object NOT managed by dbt (databases, schemas, warehouses, raw tables, views, procedures). Add `.sql` files to `ddls/` following the folder hierarchy.

---

## 5-Zone Architecture

| Zone | Prefix | Schema | Materialization | Purpose |
|------|--------|--------|-----------------|---------|
| **Transient** | `trn_` | `transient` | `table` | Truncate & reload. Technical validation. |
| **Bronze** | `brz_` | `bronze` | `incremental` | Append-only raw history. Metadata tagging. |
| **Silver** | `slv_` | `silver` | `table` / `ephemeral` | Dedup, standardize, business validation. |
| **Gold** | `dim_` / `fct_` | `gold` | `table` | Star schema (dimensions + facts). |
| **Gold Analytics** | `agg_` | `gold_analytics` | `table` | Pre-aggregated BI-ready models. |

---

## Customizing for Your Data

### dbt Models

1. **Replace or add seeds** in `dbt-project/seeds/` and update transient models to `ref('your_seed')`.
2. **Define your raw layer** in `dbt-project/models/transient/_transient__sources.yml` (database/schema/identifiers).
3. **Add transient models** (`trn_*`) for landing and technical validation.
4. **Add bronze models** (`brz_*`) for append-only history with metadata tags.
5. **Add silver models** with `_validated/` ephemeral layer for DRY validation, clean models, and reject tables.
6. **Add gold models** (`dim_*`, `fct_*`) for star schema and `agg_*` for pre-aggregations.
7. **Add schema tests** in `_<zone>__models.yml` files within each zone folder.
8. **Add singular tests** in `dbt-project/tests/` for grain, consistency, or business rules.
9. **Add snapshots** in `dbt-project/snapshots/` for any entity that needs change tracking.

### DDLs (Snowflake Objects)

1. **Databases** — add files to `ddls/_account/databases/<DB_NAME>.sql`
2. **Warehouses** — add files to `ddls/_account/warehouses/<WH_NAME>.sql`
3. **Schemas** — add files to `ddls/<DATABASE>/_schemas/<SCHEMA_NAME>.sql`
4. **Tables/Views/etc** — add files to `ddls/<DATABASE>/<SCHEMA>/<object_type>/<name>.sql`
5. Use `CREATE OR ALTER` for databases, schemas, warehouses, and tables (preserves grants)
6. Use `CREATE OR REPLACE` for procedures and functions (Snowflake limitation)
7. Always use **fully qualified names** (e.g. `APP_DB.RAW.CUSTOMERS`)

---

## Git Workflow: Feature Promotion

This project uses **feature promotion** — each feature branch is merged independently to `dev`, `uat`, and `main`. You never promote entire branches (`dev → uat → main`).

### Why Feature Promotion?

With branch promotion, if two developers merge to `uat`, a PR from `uat → main` carries **both** changes. If only one is validated by business, you're stuck. Feature promotion solves this:

```
main (= prod, source of truth)
  ├── feature/X (user A)
  │     ├── PR → dev   ← developer testing
  │     ├── PR → uat   ← business validation ✅
  │     └── PR → main  ← production (only after validation)
  │
  └── feature/Y (user B)
        ├── PR → dev   ← developer testing
        └── PR → uat   ← business validation ⏳ still waiting
```

User A's work goes to prod independently. User B waits. No cherry-picking needed.

### Rules

1. **Always branch from `main`** — not from `dev` or `uat`
2. **One feature = one branch = one deployable unit** — if it needs separate validation, it needs a separate branch
3. **`dev` and `uat` are testing environments** — they accumulate changes and can be reset to `main` periodically
4. **`main` is always clean** — only validated, reviewed code lands here

### Developer Steps

```bash
# 1. Branch from main
git checkout main && git checkout -b feature/add-model

# 2. Develop locally
cd dbt-project && dbt build --target dev

# 3. Push and open PR to dev (developer testing)
git push -u origin feature/add-model
gh pr create --base dev --title "Add customer model"

# 4. After code review, merge to dev. Then PR to uat (business validation)
gh pr create --base uat --title "Add customer model - UAT"

# 5. After business validation, PR to main (production)
gh pr create --base main --title "Add customer model"
```

### Resetting dev / uat

Periodically reset testing branches to match production:

```bash
git checkout uat && git reset --hard main && git push --force origin uat
git checkout dev && git reset --hard main && git push --force origin dev
```

---

## CI/CD (GitHub Actions)

### dbt Workflows (trigger on `dbt-project/**` changes)
- **CI (`dbt_ci.yml`):** On PR to `dev`, `uat`, or `main` — lints SQL, clones data into an isolated PR schema in `_DB_UTILS`, runs `dbt build -s 'state:modified+' --defer` for slim CI.
- **CD (`dbt_cd.yml`):** On push (merge) to `dev`, `uat`, or `main` — runs `dbt build -s 'state:modified+'` to the target environment and uploads the new manifest artifact.
- **Teardown (`dbt_teardown.yml`):** On PR close — drops the PR schema via `drop_pr_schemas` macro.

### DDL Workflows (trigger on `ddls/**` changes)
- **CI (`ddl_ci.yml`):** On PR — lints DDL SQL and validates syntax against Snowflake.
- **CD (`ddl_cd.yml`):** On merge — deploys changed DDL files to Snowflake in dependency order.

### Branch Protection
- Configure "Require branches to be up to date before merging" to prevent stale PRs.
- See `.github/branch-protection.md` for full setup instructions.

Required GitHub Secrets: `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`, `SNOWFLAKE_PASSWORD`, `SNOWFLAKE_ROLE`, `SNOWFLAKE_WAREHOUSE`, `SNOWFLAKE_DATABASE`, `SNOWFLAKE_CI_DATABASE`, `SNOWFLAKE_CI_ROLE`.

---

## Pre-commit Hooks

This project includes a `.pre-commit-config.yaml` that enforces code quality before every commit:

- **SQLFluff lint (dbt):** Checks `dbt-project/**/*.sql` against `dbt-project/.sqlfluff` (jinja templater)
- **SQLFluff lint (DDLs):** Checks `ddls/**/*.sql` against `ddls/.sqlfluff` (raw templater)
- **YAML validation:** Ensures all `.yml` files are valid
- **Trailing whitespace & EOF:** Cleans up formatting
- **Large files:** Prevents accidental large file commits
- **Branch protection:** Blocks direct commits to `main`

To set up:
```bash
pip install pre-commit
pre-commit install
```

To run manually on all files:
```bash
pre-commit run --all-files
```

---

## File Layout Summary

```
dbt-workflow/
├── dbt-project/                     # dbt models, macros, configs
│   ├── dbt_project.yml
│   ├── profiles.yml
│   ├── packages.yml
│   ├── dbt-requirements.txt
│   ├── .sqlfluff                    # SQL linting (jinja templater)
│   ├── models/
│   │   ├── transient/               # Zone 1: trn_* (landing, technical validation)
│   │   ├── bronze/                  # Zone 2: brz_* (append-only history)
│   │   ├── silver/                  # Zone 3: slv_* (dedup, business validation)
│   │   │   └── _validated/          # Ephemeral validation layer (DRY)
│   │   ├── gold/                    # Zone 4: dim_*, fct_* (star schema)
│   │   └── gold_analytics/          # Zone 5: agg_* (pre-aggregated)
│   ├── macros/                      # Schema routing, cloning, metadata
│   ├── seeds/                       # raw_*.csv (dev only)
│   ├── snapshots/                   # SCD2 snap_*
│   ├── tests/                       # Singular tests
│   └── analyses/                    # Ad-hoc SQL
│
├── ddls/                            # Snowflake DDLs (CREATE OR ALTER)
│   ├── .sqlfluff                    # SQL linting (raw templater)
│   ├── _account/                    # Databases, warehouses
│   ├── _DB_UTILS/                   # _DB_UTILS database objects
│   └── APP_DB/                      # APP_DB database objects
│       ├── _schemas/                # Schema definitions
│       └── RAW/                     # Tables, views, stages, etc.
│
├── .github/
│   ├── workflows/                   # dbt + DDL CI/CD workflows
│   └── branch-protection.md         # GitHub settings documentation
│
├── scripts/
│   └── init_project.py              # Template initializer (customize names)
│
├── .pre-commit-config.yaml          # Pre-commit hooks (both folders)
├── .gitignore
├── README.md
├── TEMPLATE_GUIDE.md                # This file
├── DBT_BEST_PRACTICES.md            # dbt patterns, anti-patterns, limitations
└── ANALYSIS.md                      # Project analysis
```

You can use this template as the single starting point for all your dbt + Snowflake projects.
