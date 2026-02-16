# dbt-workflow Project Analysis

**Maintainer:** Anouar Zbaida

---

## 1. What This Project Does (Brief)

This is a **dbt + Snowflake** project with **GitHub Actions CI/CD** and a **DDLs folder** for Snowflake infrastructure:

- **dbt Models (`dbt-project/`):** Builds a **5-zone medallion pipeline**: Transient (landing) → Bronze (raw history) → Silver (cleaned, validated) → Gold (star schema) → Gold Analytics (pre-aggregated). Data is sourced from **seeds** (CSV, dev only) or **Snowflake sources** (uat/prod) for customers, orders, order_items, and products.
- **DDLs (`ddls/`):** Manages all Snowflake objects not created by dbt — databases, warehouses, schemas, tables, views, procedures — using `CREATE OR ALTER` to preserve grants. Folder hierarchy mirrors Snowflake's object hierarchy.
- **dbt CI:** On pull requests, runs **SQLFluff lint** then **slim CI** (only modified models + dependencies) in an **isolated PR schema** in `_DB_UTILS` with data cloning and sampling; defers to the target environment for unchanged models.
- **dbt CD:** On merge, runs **incremental deploy** (`state:modified+`) to the target environment and uploads the new manifest.
- **DDL CI:** On pull requests affecting `ddls/`, lints SQL and validates syntax against Snowflake.
- **DDL CD:** On merge, deploys changed DDL files to Snowflake in dependency order.
- **Teardown:** On PR close, drops the temporary PR schema in `_DB_UTILS`.
- **Linting:** Dual SQLFluff configs — `jinja` templater for dbt, `raw` templater for DDLs — enforced via pre-commit hooks and CI.
- **Branch protection:** Stale PRs must re-validate after new merges to base branch.

So: **transform raw data through 5 zones into star schema and BI-ready aggregations, manage Snowflake infrastructure as code, with safe multi-branch CI/CD, SQL linting, and automated schema lifecycle management.**

---

## 2. Alignment With dbt + Snowflake Best Practices

| Area | Status | Notes |
|------|--------|--------|
| **Project structure** | ✅ Strong | Dual-folder layout: `dbt-project/` for dbt, `ddls/` for infrastructure. 5-zone medallion architecture. Path-based CI/CD. |
| **Naming** | ✅ Strong | Zone-specific prefixes: `trn_*`, `brz_*`, `slv_*`, `dim_*/fct_*`, `agg_*`; seeds as `raw_*`. |
| **Materialization** | ✅ Strong | Transient as table (truncate & reload), Bronze as incremental (append-only), Silver as table + ephemeral validated, Gold/Analytics as table. |
| **Data quality** | ✅ Strong | Two-stage reject pattern (technical in transient, business in silver). Ephemeral validated models for DRY validation logic. |
| **Documentation & tests** | ✅ Strong | Per-zone schema YAML with descriptions and tests (unique, not_null, relationships, accepted_values). |
| **Sources** | ✅ Good | `_transient__sources.yml` defines Fivetran raw source with conditional logic (seeds in dev, sources in uat/prod). |
| **Refs only** | ✅ Good | No raw table names; `ref()` for seeds and inter-model references, `source()` for external data. |
| **Profiles** | ✅ Strong | Env vars for credentials; separate dev/uat/prod/ci targets; no secrets in repo. |
| **Snowflake** | ✅ Good | Correct adapter; multi-thread; zero-copy cloning for CI; masked-data role for PII. |
| **DDLs** | ✅ Strong | `CREATE OR ALTER` preserves grants; folder hierarchy mirrors Snowflake; one file per object; fully qualified names. |
| **CI/CD** | ✅ Strong | Path-based triggers, multi-branch slim CI (dev/uat/main), defer to target env, PR schema isolation in `_DB_UTILS`, DDL deployment in dependency order, stale PR protection. |
| **Packages** | ✅ Good | dbt_utils, dbt_project_evaluator (conditional), dbt_expectations, codegen. |
| **Snapshots** | ✅ Good | SCD Type 2 snapshot for customers (`snap_customers.sql`). |
| **Singular tests** | ✅ Good | `tests/fct_orders_grain.sql` validates fact table grain. |
| **SQLFluff** | ✅ Strong | Dual configs: jinja for dbt, raw for DDLs. Snowflake dialect. Pre-commit and CI integration for both folders. |
| **Pre-commit** | ✅ Strong | Hooks for SQLFluff lint (both dbt and DDL SQL), YAML validation, trailing whitespace, large files, branch protection. |
| **Metadata tagging** | ✅ Good | `tag_columns` macro adds `_source_system`, `_domain`, `_sensitivity_tag`, `_processed_at`, `_batch_id`. |
| **Branch protection** | ✅ Strong | Documented setup for stale PR protection, required status checks, no-bypass policy. |

**Verdict:** This is a comprehensive, production-grade dbt + Snowflake template that covers all major best practices, including Snowflake infrastructure-as-code via the DDLs folder.

---

## 3. Potential Further Enhancements

- **dbt-requirements.txt:** Consider pinning to a specific minor version (e.g. `dbt-snowflake==1.8.*`) for fully reproducible CI/CD.
- **dbt docs in CI:** Optionally run `dbt docs generate` in CI to catch documentation issues early.
- **Additional snapshots:** Add more SCD Type 2 snapshots as needed (products, orders).
- **dbt_project_evaluator:** Enable by default in dev (`ENABLE_DBT_PROJECT_EVALUATOR=true`) to catch modeling issues early.
- **DDL testing:** Add more sophisticated DDL validation (e.g. comparing against live Snowflake state).

---

## 4. Can This Be Used as a Template? What's Needed?

**Yes.** It's a complete, scenario-rich template ready for reuse.

**What's included:**
- ✅ Dual-folder structure (`dbt-project/` + `ddls/`) with path-based CI/CD
- ✅ 5-zone medallion architecture with clear separation
- ✅ Two-stage reject pattern (technical + business)
- ✅ Ephemeral validated models (DRY pattern)
- ✅ Conditional source (seeds vs Fivetran) for multi-environment
- ✅ Multi-branch CI/CD (dev/uat/main → DEV/UAT/PROD) for both dbt and DDLs
- ✅ PR-isolated testing with data cloning and PII masking
- ✅ Slim CI with state/defer and graceful first-run fallback
- ✅ DDL management with CREATE OR ALTER (preserves grants)
- ✅ DDL deployment in dependency order
- ✅ SCD Type 2 snapshot example
- ✅ Singular and schema tests
- ✅ Dual SQLFluff linting (jinja for dbt, raw for DDLs) with pre-commit hooks
- ✅ Branch protection documentation (stale PR prevention)
- ✅ TEMPLATE_GUIDE.md with quick start and customization instructions
- ✅ Environment-aware schema routing
- ✅ Stored procedure for data cloning

**To start a new project:**
1. Clone this repo
2. Rename project in `dbt-project/dbt_project.yml`
3. Set environment variables
4. Replace seed data / define sources
5. Customize DDLs for your Snowflake environment
6. Start building models following the zone patterns

---

## 5. Creator / Maintainer

**Anouar Zbaida** — Maintainer. See README and TEMPLATE_GUIDE.md.

---

## 6. Goal: One Template for All Scenarios

This template covers all common dbt + Snowflake scenarios:

1. **Landing from seeds** (dev) and **sources** (uat/prod) via conditional Jinja
2. **5-zone medallion** with zone-level materialization and tagging
3. **Two-stage data quality** with reject tables preserving full history
4. **Star schema** (dimensions + facts) with BI-ready aggregations
5. **SCD Type 2** snapshots for change tracking
6. **Snowflake infrastructure as code** via `ddls/` with CREATE OR ALTER
7. **Multi-branch CI/CD** with path-based triggers, PR isolation, slim builds, DDL deployment, and automated teardown
8. **Dual SQL linting** via SQLFluff (jinja for dbt, raw for DDLs) with pre-commit hooks and CI enforcement
9. **Schema tests** and **singular tests** per zone
10. **Stale PR protection** via branch protection rules

After cloning, developers can immediately start building models with CI/CD, DDL management, linting, and testing out of the box.
