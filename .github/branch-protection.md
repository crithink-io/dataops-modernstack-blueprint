# Branch Protection Setup

Configure these settings in **GitHub repo Settings > Branches > Add rule**.

## Required for `main` branch (repeat for `uat` and `dev`)

### Branch name pattern: `main`

- [x] **Require a pull request before merging**
  - [x] Require approvals (1+)
  - [x] Dismiss stale pull request approvals when new commits are pushed

- [x] **Require status checks to pass before merging**
  - [x] **Require branches to be up to date before merging** (KEY SETTING)
  - Required status checks:
    - `dbt_lint` (from dbt_ci.yml)
    - `dbt_build` (from dbt_ci.yml)
    - `ddl_lint` (from ddl_ci.yml)
    - `ddl_validate` (from ddl_ci.yml)

- [x] **Do not allow bypassing the above settings**

## What this achieves

### Stale PR protection
When PR2 merges to `main`, any previously-validated PR1 becomes "out of date":
1. GitHub blocks PR1's merge button
2. Developer must click "Update branch" (rebase from main)
3. CI re-runs automatically
4. If CI fails, merge stays blocked

### Both folder checks required
- PRs that modify `dbt-project/` trigger `dbt_lint` + `dbt_build`
- PRs that modify `ddls/` trigger `ddl_lint` + `ddl_validate`
- PRs that modify both trigger all four checks
- Merge is blocked until ALL triggered checks pass

### No bypass
Even admins cannot bypass these rules (unless you uncheck the "Do not allow bypassing" option).

## Notes on path-filtered required checks

GitHub marks path-filtered status checks as "Expected - Waiting for status to be reported"
if the workflow didn't trigger (e.g., a DDL-only PR won't trigger dbt checks).

**Solution**: In the required status checks, only add checks that should ALWAYS run.
Alternatively, use a "pass-through" job pattern or configure required checks per path
using GitHub's newer "required status checks per path" feature (available on GitHub Enterprise)
or use a GitHub App like "paths-filter" for more granular control.
