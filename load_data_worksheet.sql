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
CREATE OR REPLACE FILE FORMAT parquet_fmt
  TYPE = 'PARQUET';

-- ============================================================
-- Step 2: Verify the stage and see what files are available
-- ============================================================
LIST @"snowflakeap_S3_STAGE";

-- ============================================================
-- Step 3: Query Parquet directly to see the structure
-- Parquet stores data as a single VARIANT column with nested fields
-- ============================================================
SELECT $1 FROM @"snowflakeap_S3_STAGE"/sample_users.parquet
  (FILE_FORMAT => parquet_fmt)
LIMIT 1;

-- ============================================================
-- Step 4: Create the table by extracting Parquet fields
-- Parquet preserves actual column names!
-- ============================================================
CREATE OR REPLACE TABLE "USERS" AS
SELECT
  $1:USER_ID::NUMBER AS USER_ID,
  $1:FIRST_NAME::VARCHAR AS FIRST_NAME,
  $1:LAST_NAME::VARCHAR AS LAST_NAME
FROM @"snowflakeap_S3_STAGE"/sample_users.parquet
  (FILE_FORMAT => parquet_fmt);

-- ============================================================
-- Step 4: Verify the data was loaded successfully
-- ============================================================

-- Show table structure
DESCRIBE TABLE "USERS";

-- Count total rows
SELECT COUNT(*) as total_rows FROM "USERS";

-- View all rows (small dataset)
SELECT * FROM "USERS";

-- View with explicit column names (Parquet preserves actual column names!)
SELECT
    "USER_ID",
    "FIRST_NAME",
    "LAST_NAME"
FROM "USERS"
ORDER BY "USER_ID";
