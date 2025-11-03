-- Test that Snowflake CANNOT access secret/ directory
USE DATABASE "snowflakeap_DB";
USE SCHEMA "snowflakeap_SC";
USE WAREHOUSE "snowflakeap_WH";

-- Try to create a stage pointing to secret/ (should fail)
CREATE OR REPLACE STAGE "TEST_SECRET_STAGE"
  STORAGE_INTEGRATION = "snowflakeap_S3_INTEGRATION"
  URL = 's3://snowflakeap-snowflak-mxpcztcf1zbh1sqq7r1p47ybcrcdqeuw2b-s3alias/secret/'
  AWS_ACCESS_POINT_ARN = 'arn:aws:s3:eu-west-2:160071257600:accesspoint/snowflakeap-snowflake-ap';

-- Try to list files in secret/ (should fail or show empty)
LIST @"TEST_SECRET_STAGE";

-- Clean up
DROP STAGE IF EXISTS "TEST_SECRET_STAGE";
