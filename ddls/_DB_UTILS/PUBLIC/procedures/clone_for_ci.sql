/*
=============================================================================
  Stored Procedure: _DB_UTILS.PUBLIC.CLONE_FOR_CI

  Purpose:
    Clones specific tables (or all tables in given schemas) from a source
    database into a PR-specific schema within _DB_UTILS.
    Used by the CI workflow to create isolated test environments for each PR.

  Parameters:
    - SOURCE_DB       (VARCHAR): Source database name (e.g. 'APP_DB_DEV')
    - SCHEMA_LIST     (VARCHAR): Comma-separated schemas used when TABLE_LIST='*'
                                 (e.g. 'TRANSIENT,BRONZE,SILVER,GOLD,GOLD_ANALYTICS')
    - TARGET_SCHEMA   (VARCHAR): PR schema name (e.g. 'PR_42__A1B2C3D')
    - ENV_TYPE        (VARCHAR): Environment type ('dev', 'uat', 'prod')
    - SAMPLE_PCT      (NUMBER):  Percentage of rows to sample (0 = full clone)
    - ROLE_NAME       (VARCHAR): Role to use for data access (masked-data role)
    - TABLE_LIST      (VARCHAR): '*' = clone all tables in SCHEMA_LIST (default).
                                 Otherwise: comma-separated 'SCHEMA.TABLE' pairs
                                 to clone only specific objects — e.g.
                                 'SILVER.SLV_CUSTOMERS,GOLD.DIM_CUSTOMERS'

  Behaviour:
    - Creates the target schema in _DB_UTILS if it does not exist.
    - TABLE_LIST = '*': iterates INFORMATION_SCHEMA to find all tables in each
      schema from SCHEMA_LIST and clones every one of them.
    - TABLE_LIST = specific pairs: clones only the listed tables directly,
      without scanning the information schema.
    - If SAMPLE_PCT = 0: creates zero-copy clones (no storage cost).
    - If SAMPLE_PCT > 0: creates tables via CTAS with SAMPLE(SAMPLE_PCT).
    - Switches to ROLE_NAME before reading source data to enforce masking
      policies (PII columns are masked for the CI role).
    - Prefixes cloned tables with source schema name to avoid collisions
      (e.g. SILVER.SLV_CUSTOMERS -> SILVER_SLV_CUSTOMERS).

  Usage — clone all schemas (first run / no manifest):
    CALL _DB_UTILS.PUBLIC.CLONE_FOR_CI(
      'APP_DB_DEV', 'TRANSIENT,BRONZE,SILVER,GOLD,GOLD_ANALYTICS',
      'PR_42__A1B2C3D', 'dev', 10, 'DBT_CI_MASKED_ROLE', '*'
    );

  Usage — clone only impacted tables (slim CI with manifest):
    CALL _DB_UTILS.PUBLIC.CLONE_FOR_CI(
      'APP_DB_DEV', '',
      'PR_42__A1B2C3D', 'dev', 0, 'DBT_CI_MASKED_ROLE',
      'SILVER.SLV_CUSTOMERS,GOLD.DIM_CUSTOMERS,GOLD.FCT_ORDERS'
    );

  Notes:
    - The calling role must have USAGE on _DB_UTILS and CREATE SCHEMA privileges.
    - The masked-data role must have SELECT on source tables with masking policies.
    - Called by the dbt macro `clone_for_ci` in the CI workflow.
=============================================================================
*/

CREATE OR REPLACE PROCEDURE _DB_UTILS.PUBLIC.CLONE_FOR_CI(
    SOURCE_DB       VARCHAR,
    SCHEMA_LIST     VARCHAR,
    TARGET_SCHEMA   VARCHAR,
    ENV_TYPE        VARCHAR,
    SAMPLE_PCT      NUMBER,
    ROLE_NAME       VARCHAR,
    TABLE_LIST      VARCHAR DEFAULT '*'
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    schema_array    ARRAY;
    table_array     ARRAY;
    current_schema  VARCHAR;
    table_name      VARCHAR;
    prefixed_name   VARCHAR;
    entry           VARCHAR;
    dot_pos         INTEGER;
    clone_sql       VARCHAR;
    table_count     NUMBER DEFAULT 0;
    i               NUMBER DEFAULT 0;
    original_role   VARCHAR;
    result_msg      VARCHAR;
    cur CURSOR FOR
        SELECT TABLE_NAME
        FROM IDENTIFIER(:SOURCE_DB || '.INFORMATION_SCHEMA.TABLES')
        WHERE TABLE_SCHEMA = :current_schema
          AND TABLE_TYPE = 'BASE TABLE';
BEGIN
    original_role := CURRENT_ROLE();
    EXECUTE IMMEDIATE 'CREATE SCHEMA IF NOT EXISTS _DB_UTILS.' || :TARGET_SCHEMA;
    EXECUTE IMMEDIATE 'USE ROLE ' || :ROLE_NAME;

    IF (TABLE_LIST = '*') THEN
        -- ---------------------------------------------------------------
        -- Full mode: scan each schema and clone every table found.
        -- ---------------------------------------------------------------
        schema_array := SPLIT(:SCHEMA_LIST, ',');

        FOR i IN 0 TO ARRAY_SIZE(schema_array) - 1 DO
            current_schema := TRIM(schema_array[i]);

            OPEN cur;
            LOOP
                FETCH cur INTO table_name;
                IF (SQLCODE != 0) THEN LEAVE; END IF;

                prefixed_name := current_schema || '_' || table_name;

                IF (SAMPLE_PCT = 0) THEN
                    clone_sql := 'CREATE OR REPLACE TABLE _DB_UTILS.' || :TARGET_SCHEMA || '.' || :prefixed_name
                              || ' CLONE ' || :SOURCE_DB || '.' || :current_schema || '.' || :table_name;
                ELSE
                    clone_sql := 'CREATE OR REPLACE TABLE _DB_UTILS.' || :TARGET_SCHEMA || '.' || :prefixed_name
                              || ' AS SELECT * FROM ' || :SOURCE_DB || '.' || :current_schema || '.' || :table_name
                              || ' SAMPLE (' || :SAMPLE_PCT || ')';
                END IF;

                EXECUTE IMMEDIATE :clone_sql;
                table_count := table_count + 1;
            END LOOP;
            CLOSE cur;
        END FOR;

    ELSE
        -- ---------------------------------------------------------------
        -- Slim mode: clone only the specific SCHEMA.TABLE pairs provided.
        -- Each entry is 'SCHEMA.TABLE_NAME' (e.g. 'SILVER.SLV_CUSTOMERS').
        -- ---------------------------------------------------------------
        table_array := SPLIT(:TABLE_LIST, ',');

        FOR i IN 0 TO ARRAY_SIZE(table_array) - 1 DO
            entry          := TRIM(table_array[i]);
            dot_pos        := POSITION('.' IN entry);
            current_schema := TRIM(LEFT(entry, :dot_pos - 1));
            table_name     := TRIM(SUBSTRING(entry, :dot_pos + 1));
            prefixed_name  := current_schema || '_' || table_name;

            IF (SAMPLE_PCT = 0) THEN
                clone_sql := 'CREATE OR REPLACE TABLE _DB_UTILS.' || :TARGET_SCHEMA || '.' || :prefixed_name
                          || ' CLONE ' || :SOURCE_DB || '.' || :current_schema || '.' || :table_name;
            ELSE
                clone_sql := 'CREATE OR REPLACE TABLE _DB_UTILS.' || :TARGET_SCHEMA || '.' || :prefixed_name
                          || ' AS SELECT * FROM ' || :SOURCE_DB || '.' || :current_schema || '.' || :table_name
                          || ' SAMPLE (' || :SAMPLE_PCT || ')';
            END IF;

            EXECUTE IMMEDIATE :clone_sql;
            table_count := table_count + 1;
        END FOR;

    END IF;

    EXECUTE IMMEDIATE 'USE ROLE ' || :original_role;

    result_msg := 'Clone completed. ' || :table_count || ' tables cloned into _DB_UTILS.' || :TARGET_SCHEMA
               || ' (mode=' || IFF(:TABLE_LIST = '*', 'full', 'slim')
               || ', env=' || :ENV_TYPE || ', sample=' || :SAMPLE_PCT || '%).';
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
    VARCHAR, VARCHAR, VARCHAR, VARCHAR, NUMBER, VARCHAR, VARCHAR
) TO ROLE DBT_CI_ROLE;

-- The masked-data role needs SELECT on source tables
-- (Masking policies should be applied at the column level in the source DB)
-- GRANT SELECT ON ALL TABLES IN SCHEMA APP_DB_DEV.TRANSIENT TO ROLE DBT_CI_MASKED_ROLE;
-- GRANT SELECT ON ALL TABLES IN SCHEMA APP_DB_DEV.BRONZE TO ROLE DBT_CI_MASKED_ROLE;
-- ... repeat for each schema
