/*
=============================================================================
  Stored Procedure: _DB_UTILS.PUBLIC.CLONE_FOR_CI

  Purpose:
    Clones source database schemas into a PR-specific schema within _DB_UTILS.
    Used by the CI workflow to create isolated test environments for each PR.

  Parameters:
    - SOURCE_DB       (VARCHAR): Source database name (e.g. 'APP_DB_DEV')
    - SCHEMA_LIST     (VARCHAR): Comma-separated list of schemas to clone
                                 (e.g. 'TRANSIENT,BRONZE,SILVER,GOLD,GOLD_ANALYTICS')
    - TARGET_SCHEMA   (VARCHAR): PR schema name (e.g. 'PR_42__A1B2C3D')
    - ENV_TYPE        (VARCHAR): Environment type ('dev', 'uat', 'prod')
    - SAMPLE_PCT      (NUMBER):  Percentage of rows to sample (0 = full clone)
    - ROLE_NAME       (VARCHAR): Role to use for data access (masked-data role)

  Behaviour:
    - Creates the target schema in _DB_UTILS if it does not exist.
    - For each schema in SCHEMA_LIST, iterates over all tables in SOURCE_DB.
    - If SAMPLE_PCT = 0: creates zero-copy clones (no storage cost).
    - If SAMPLE_PCT > 0: creates tables via CTAS with SAMPLE(SAMPLE_PCT).
    - Switches to ROLE_NAME before reading source data to enforce masking
      policies (PII columns are masked for the CI role).
    - Prefixes cloned tables with the source schema name to avoid collisions
      (e.g. TRANSIENT_CUSTOMERS, BRONZE_CUSTOMERS).
    - Logs progress for each table.

  Usage:
    CALL _DB_UTILS.PUBLIC.CLONE_FOR_CI(
      'APP_DB_DEV',
      'TRANSIENT,BRONZE,SILVER,GOLD,GOLD_ANALYTICS',
      'PR_42__A1B2C3D',
      'dev',
      10,
      'DBT_CI_MASKED_ROLE'
    );

  Notes:
    - The calling role (e.g. DBT_CI_ROLE) must have USAGE on _DB_UTILS and
      CREATE SCHEMA privileges.
    - The masked-data role must have SELECT on source tables with appropriate
      masking policies applied.
    - This procedure is called by the dbt macro `clone_for_ci` in CI workflows.
=============================================================================
*/

CREATE OR REPLACE PROCEDURE _DB_UTILS.PUBLIC.CLONE_FOR_CI(
    SOURCE_DB       VARCHAR,
    SCHEMA_LIST     VARCHAR,
    TARGET_SCHEMA   VARCHAR,
    ENV_TYPE        VARCHAR,
    SAMPLE_PCT      NUMBER,
    ROLE_NAME       VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    schema_array    ARRAY;
    current_schema  VARCHAR;
    table_name      VARCHAR;
    prefixed_name   VARCHAR;
    clone_sql       VARCHAR;
    table_count     NUMBER DEFAULT 0;
    schema_idx      NUMBER DEFAULT 0;
    original_role   VARCHAR;
    result_msg      VARCHAR;
    cur CURSOR FOR
        SELECT TABLE_NAME
        FROM IDENTIFIER(:SOURCE_DB || '.INFORMATION_SCHEMA.TABLES')
        WHERE TABLE_SCHEMA = :current_schema
          AND TABLE_TYPE = 'BASE TABLE';
BEGIN
    -- ---------------------------------------------------------------
    -- 1. Save the current role so we can restore it after cloning.
    -- ---------------------------------------------------------------
    original_role := CURRENT_ROLE();

    -- ---------------------------------------------------------------
    -- 2. Create the target PR schema in _DB_UTILS.
    -- ---------------------------------------------------------------
    EXECUTE IMMEDIATE 'CREATE SCHEMA IF NOT EXISTS _DB_UTILS.' || :TARGET_SCHEMA;

    -- ---------------------------------------------------------------
    -- 3. Switch to the masked-data role for reading source data.
    --    This ensures PII columns are masked during the clone.
    -- ---------------------------------------------------------------
    EXECUTE IMMEDIATE 'USE ROLE ' || :ROLE_NAME;

    -- ---------------------------------------------------------------
    -- 4. Parse the comma-separated schema list into an array.
    -- ---------------------------------------------------------------
    schema_array := SPLIT(:SCHEMA_LIST, ',');

    -- ---------------------------------------------------------------
    -- 5. Iterate over each source schema.
    -- ---------------------------------------------------------------
    FOR schema_idx IN 0 TO ARRAY_SIZE(schema_array) - 1 DO
        current_schema := TRIM(schema_array[schema_idx]);

        OPEN cur;
        LOOP
            FETCH cur INTO table_name;
            IF (SQLCODE != 0) THEN
                LEAVE;
            END IF;

            -- Prefix cloned table name with source schema to avoid collisions.
            -- e.g. TRANSIENT.CUSTOMERS -> TRANSIENT_CUSTOMERS
            prefixed_name := current_schema || '_' || table_name;

            IF (SAMPLE_PCT = 0) THEN
                -- Full zero-copy clone (no additional storage cost)
                clone_sql := 'CREATE OR REPLACE TABLE _DB_UTILS.' || :TARGET_SCHEMA || '.' || :prefixed_name
                          || ' CLONE ' || :SOURCE_DB || '.' || :current_schema || '.' || :table_name;
            ELSE
                -- Sampled CTAS for lower environments (dev / integration)
                clone_sql := 'CREATE OR REPLACE TABLE _DB_UTILS.' || :TARGET_SCHEMA || '.' || :prefixed_name
                          || ' AS SELECT * FROM ' || :SOURCE_DB || '.' || :current_schema || '.' || :table_name
                          || ' SAMPLE (' || :SAMPLE_PCT || ')';
            END IF;

            EXECUTE IMMEDIATE :clone_sql;
            table_count := table_count + 1;
        END LOOP;
        CLOSE cur;
    END FOR;

    -- ---------------------------------------------------------------
    -- 6. Restore the original role.
    -- ---------------------------------------------------------------
    EXECUTE IMMEDIATE 'USE ROLE ' || :original_role;

    result_msg := 'Clone completed. ' || :table_count || ' tables cloned into _DB_UTILS.' || :TARGET_SCHEMA
               || ' (env=' || :ENV_TYPE || ', sample=' || :SAMPLE_PCT || '%).';
    RETURN result_msg;
END;
$$;


/*
=============================================================================
  Grant permissions for the CI role to execute the procedure.
  Adjust role names to match your Snowflake RBAC setup.
=============================================================================
*/

-- Grant usage on _DB_UTILS to CI roles
GRANT USAGE ON DATABASE _DB_UTILS TO ROLE DBT_CI_ROLE;
GRANT USAGE ON SCHEMA _DB_UTILS.PUBLIC TO ROLE DBT_CI_ROLE;
GRANT CREATE SCHEMA ON DATABASE _DB_UTILS TO ROLE DBT_CI_ROLE;

-- Grant execute on the stored procedure
GRANT USAGE ON PROCEDURE _DB_UTILS.PUBLIC.CLONE_FOR_CI(
    VARCHAR, VARCHAR, VARCHAR, VARCHAR, NUMBER, VARCHAR
) TO ROLE DBT_CI_ROLE;

-- The masked-data role needs SELECT on source tables
-- (Masking policies should be applied at the column level in the source DB)
-- GRANT SELECT ON ALL TABLES IN SCHEMA APP_DB_DEV.TRANSIENT TO ROLE DBT_CI_MASKED_ROLE;
-- GRANT SELECT ON ALL TABLES IN SCHEMA APP_DB_DEV.BRONZE TO ROLE DBT_CI_MASKED_ROLE;
-- ... repeat for each schema
