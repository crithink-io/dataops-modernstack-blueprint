# Contributing to dataops-modernstack-blueprint

Thanks for your interest in contributing! This template is designed to help teams ship Snowflake + dbt projects faster, and your contributions make it better for everyone.

## How to Contribute

### Reporting Issues

- Open an [issue](https://github.com/crithink-io/dataops-modernstack-blueprint/issues) describing the problem or suggestion
- Include the context: which file, what you expected, what happened instead
- For bugs in CI/CD workflows, include the GitHub Actions run log if possible

### Submitting Changes

1. **Fork** the repository
2. **Create a feature branch** from `main`:
   ```bash
   git checkout -b feature/your-change
   ```
3. **Make your changes** — follow the conventions below
4. **Test locally** if your change affects dbt models or macros:
   ```bash
   cd dbt-project
   dbt build --target dev
   sqlfluff lint models/ macros/
   ```
5. **Commit** with a clear message:
   ```bash
   git commit -m "Add: description of what you added"
   ```
6. **Push** and open a pull request to `main`

### What We're Looking For

- New dbt patterns or macros that are broadly useful
- Improvements to CI/CD workflows (performance, reliability, new checks)
- Better documentation or examples
- Bug fixes in SQL, YAML, or workflow definitions
- Support for additional Snowflake object types in DDLs
- New data quality patterns

### Conventions

| Area | Convention |
|------|-----------|
| **SQL style** | Lowercase keywords, leading commas, explicit aliases, CTEs over subqueries |
| **Model naming** | `trn_`, `brz_`, `slv_`, `dim_`/`fct_`, `agg_` per zone |
| **File naming** | Snake_case, one model per file |
| **YAML** | One schema YAML per zone (`_<zone>__models.yml`) |
| **Commits** | Start with verb: `Add:`, `Fix:`, `Update:`, `Remove:` |
| **DDLs** | `CREATE OR ALTER` where supported, fully qualified object names |

### What to Avoid

- Changes that are project-specific rather than template-generic
- Adding dependencies to paid or proprietary tools
- Breaking changes to the init script without updating `TEMPLATE_GUIDE.md`
- Hardcoded Snowflake account/database names (use environment variables)

## Code of Conduct

Be respectful, constructive, and collaborative. We're all here to build better data platforms.

## Questions?

Open a [discussion](https://github.com/crithink-io/dataops-modernstack-blueprint/discussions) or reach out via an issue.
