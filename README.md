# Snowflake S3 Access Point Integration

This project demonstrates how to securely load data from S3 into Snowflake using **S3 Access Points** to restrict access to a specific prefix.

## Security Model

**Simple, explicit, auditable** - Snowflake can **ONLY** access files in the `202511/` prefix via S3 Access Point.

### Four Security Layers

1. **Storage Integration** (Snowflake) - Allows only `s3://access-point-alias/202511/`
2. **IAM Role Policy** - Grants Access Point permissions only (no direct bucket access)
3. **Access Point Policy** - Explicit principal (snowflakeap-role), no wildcards
4. **Bucket Policy** - Delegates to Access Point only (via `s3:DataAccessPointAccount`)

### Key Design Principles

- **No wildcards with conditions** - Access Point uses explicit principal ARN
- **Access Point only** - IAM role cannot access bucket directly
- **Simple policies** - Easy to read, audit, and reason about
- **Tested security** - Verified that `secret/` directory is inaccessible

See [SECURITY.md](SECURITY.md) for detailed security architecture.

## Quick Start

```bash
# Deploy infrastructure (creates AWS resources and Snowflake objects)
make apply

# Upload sample data to 202511/ prefix
make upload

# Verify the stage is working in Snowflake:
# LIST @snowflakeap_S3_STAGE;

# Clean up generated files
make clean
```

## Important Note about AWS_ACCESS_POINT_ARN

The Terraform configuration uses a workaround via `snowflake_execute` resource to set the `AWS_ACCESS_POINT_ARN` parameter on the stage, since the Snowflake Terraform provider doesn't natively support this parameter yet (see [GitHub issue #4080](https://github.com/snowflakedb/terraform-provider-snowflake/discussions/4080)).

The workaround automatically runs this SQL after creating the stage:
```sql
ALTER STAGE snowflakeap_S3_STAGE
SET AWS_ACCESS_POINT_ARN = '<access-point-arn>';
```

## Architecture

```
Snowflake → Storage Integration → IAM Role → S3 Access Point → S3 Bucket (202511/ only)
                                                    ↓
                                            Blocked: secret/, 202510/, 202512/, etc.
```

## Key Features

- ✅ **Prefix Isolation**: Snowflake restricted to `202511/` prefix only
- ✅ **Defense in Depth**: Multiple security layers (Access Point, IAM, Bucket Policy)
- ✅ **Explicit Deny**: Bucket policy blocks direct bucket access
- ✅ **Least Privilege**: Minimal permissions granted to Snowflake role

## Resources

- [Snowflake Storage Integration Guide](https://docs.snowflake.com/en/user-guide/data-load-s3-config-storage-integration)
- [Snowflake Storage Integration SQL](https://docs.snowflake.com/en/sql-reference/sql/create-storage-integration)
- [Terraform Provider for Snowflake](https://github.com/snowflakedb/terraform-provider-snowflake)
- [AWS S3 Access Points Documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-points.html)
- [Terraforming Snowflake Quickstart](https://quickstarts.snowflake.com/guide/terraforming_snowflake/#2)

## Testing

### Load Data Test
```bash
# Loads sample Parquet file into USERS table via Access Point
./run_worksheet.sh load_data_worksheet.sql
```

Expected: 5 rows loaded from `202511/sample_users.parquet` ✅

### Security Test
```bash
# Attempts to create stage pointing to secret/ directory
./run_worksheet.sh test_secret_access.sql
```

Expected: `Location 's3://.../secret/' is not allowed by integration` ❌ (blocked as expected)

### Manual Verification
```sql
USE DATABASE snowflakeap_DB;
USE SCHEMA snowflakeap_SC;

-- Should work (lists files in 202511/):
LIST @snowflakeap_S3_STAGE;

-- Should fail (blocked by Storage Integration):
CREATE STAGE TEST_BAD URL = 's3://<alias>/secret/';
```

## Deployment Results

✅ **Successfully deployed on 2025-11-03**

### Resources Created
- S3 Access Point: `snowflakeap-snowflake-ap`
- IAM Role: `snowflakeap-role`
- Snowflake Integration: `snowflakeap_S3_INTEGRATION`
- Snowflake Stage: `snowflakeap_S3_STAGE` (with AWS_ACCESS_POINT_ARN set)

### Files Available
| File | Description |
|------|-------------|
| `DEPLOYMENT_SUMMARY.md` | Complete deployment details and status |
| `TESTING_RESULTS.md` | Test cases and verification checklist |
| `SECURITY.md` | Detailed security architecture |
| `IMPLEMENTATION_NOTES.md` | Technical implementation details |
| `verify_access.sql` | Comprehensive access tests |

## Verified Security

| Test | Status | Result |
|------|--------|--------|
| Access 202511/ via stage | ✅ | 3 files accessible |
| Access secret/ directory | ❌ | AccessDenied (as expected) |
| Access other prefixes | ❌ | AccessDenied (as expected) |
| Direct bucket access | ❌ | Blocked by bucket policy |
