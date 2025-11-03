-- Test stage access step by step
USE DATABASE "snowflakeap_DB";
USE SCHEMA "snowflakeap_SC";
USE WAREHOUSE "snowflakeap_WH";

-- 1. List files in stage (this worked before)
LIST @"snowflakeap_S3_STAGE";

-- 2. Try to query a file directly
SELECT $1 FROM @"snowflakeap_S3_STAGE"/sample_users.parquet (FILE_FORMAT => 'parquet_fmt');

-- 3. Show stage details
DESCRIBE STAGE "snowflakeap_S3_STAGE";

-- 4. Show storage integration details
DESC INTEGRATION "snowflakeap_S3_INTEGRATION";
