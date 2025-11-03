-- ============================================================
-- Snowflake Worksheet: Load sample_users.parquet from S3
-- Copy this entire script into a Snowflake worksheet and run
-- ============================================================

-- Set context
USE DATABASE "snowflakeap_DB";
USE SCHEMA "snowflakeap_SC";
USE WAREHOUSE "snowflakeap_WH";

-- ============================================================
-- Step 1: Create a Parquet file format (temporary, in-worksheet)
-- ============================================================
CREATE OR REPLACE FILE FORMAT parquet_fmt TYPE = 'PARQUET';

-- ============================================================
-- Step 2: Verify the stage and see what files are available
-- ============================================================
LIST @"snowflakeap_S3_STAGE";

-- ============================================================
-- Step 3: Infer schema from Parquet (shows actual column names!)
-- ============================================================
SELECT * FROM TABLE(
  INFER_SCHEMA(
    LOCATION => '@"snowflakeap_S3_STAGE"/sample_users.parquet',
    FILE_FORMAT => 'parquet_fmt'
  )
);

-- ============================================================
-- Step 4: Create table using inferred schema
-- No need to manually specify columns - Parquet has them!
-- ============================================================
CREATE OR REPLACE TABLE "USERS"
USING TEMPLATE (
  SELECT ARRAY_AGG(OBJECT_CONSTRUCT(*))
  FROM TABLE(
    INFER_SCHEMA(
      LOCATION => '@"snowflakeap_S3_STAGE"/sample_users.parquet',
      FILE_FORMAT => 'parquet_fmt'
    )
  )
);

-- ============================================================
-- Step 5: Load the data
-- ============================================================
COPY INTO "USERS"
FROM @"snowflakeap_S3_STAGE"
FILES = ('sample_users.parquet')
FILE_FORMAT = (FORMAT_NAME = 'parquet_fmt')
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;

-- ============================================================
-- Step 6: Verify the data was loaded successfully
-- ============================================================

-- Show table structure
DESCRIBE TABLE "USERS";

-- Count total rows
SELECT COUNT(*) as total_rows FROM "USERS";

-- View all rows (small dataset)
SELECT * FROM "USERS" ORDER BY "USER_ID";
