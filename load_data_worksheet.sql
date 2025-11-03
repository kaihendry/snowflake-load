-- ============================================================
-- Snowflake Worksheet: Load sample_users.csv from S3
-- Copy this entire script into a Snowflake worksheet and run
-- ============================================================

-- Set context
USE DATABASE "snowflakeap_DB";
USE SCHEMA "snowflakeap_SC";
USE WAREHOUSE "snowflakeap_WH";

-- ============================================================
-- Step 1: Verify the stage and see what files are available
-- ============================================================
LIST @"snowflakeap_S3_STAGE";

-- ============================================================
-- Step 2: Infer the schema from the CSV file
-- ============================================================
SELECT *
FROM TABLE(
  INFER_SCHEMA(
    LOCATION => '@"snowflakeap_S3_STAGE"/sample_users.csv',
    FILE_FORMAT => '"snowflakeap_DB"."snowflakeap_SC"."snowflakeap_CSV_FORMAT"'
  )
);

-- ============================================================
-- Step 3: Create the table using inferred schema
-- ============================================================
CREATE OR REPLACE TABLE "USERS"
USING TEMPLATE (
  SELECT ARRAY_AGG(OBJECT_CONSTRUCT(*))
  FROM TABLE(
    INFER_SCHEMA(
      LOCATION => '@"snowflakeap_S3_STAGE"/sample_users.csv',
      FILE_FORMAT => '"snowflakeap_DB"."snowflakeap_SC"."snowflakeap_CSV_FORMAT"'
    )
  )
);

-- ============================================================
-- Step 4: Load the data from S3 into the table
-- ============================================================
COPY INTO "USERS"
FROM @"snowflakeap_S3_STAGE"
FILES = ('sample_users.csv')
FILE_FORMAT = (FORMAT_NAME = '"snowflakeap_DB"."snowflakeap_SC"."snowflakeap_CSV_FORMAT"')
ON_ERROR = 'CONTINUE'
PURGE = FALSE;

-- ============================================================
-- Step 5: Verify the data was loaded successfully
-- ============================================================

-- Show table structure
DESCRIBE TABLE "USERS";

-- Count total rows
SELECT COUNT(*) as total_rows FROM "USERS";

-- View all rows (small dataset)
SELECT * FROM "USERS";

-- View with explicit column names (inferred schema uses c1, c2, c3)
SELECT
    "c1" as USER_ID,
    "c2" as FIRST_NAME,
    "c3" as LAST_NAME
FROM "USERS"
ORDER BY "c1";
