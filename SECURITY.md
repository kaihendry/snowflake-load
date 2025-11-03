# S3 Access Point Security Implementation

## Overview
This project uses **S3 Access Points** with a **simplified, explicit security model** to restrict Snowflake's access to only the `202511/` prefix in the S3 bucket. The design prioritizes simplicity, auditability, and defense-in-depth.

## Architecture

### Components
1. **S3 Bucket**: `snowflakeap-2025-eu-west-2`
2. **S3 Access Point**: `snowflakeap-snowflake-ap`
3. **IAM Role**: `snowflakeap-role` (explicit principal, no wildcards)
4. **Snowflake Storage Integration**: Restricted to `202511/` location
5. **Snowflake Stage**: Uses Access Point alias with `AWS_ACCESS_POINT_ARN` parameter

## Security Model: Four Layers

### Layer 1: Snowflake Storage Integration
**Purpose**: First line of defense at Snowflake level

```hcl
storage_allowed_locations = [
  "s3://${access_point_alias}/202511/"
]
```

**What it blocks:**
- ❌ Cannot create stages pointing to `secret/` or any other prefix
- ❌ Snowflake SQL compilation error if attempting other paths

### Layer 2: IAM Role Policy
**Purpose**: Grants minimum required permissions via Access Point only

```hcl
# Statement 1: Object Access (explicit path)
Resource = "arn:aws:s3:eu-west-2:ACCOUNT:accesspoint/snowflakeap-snowflake-ap/object/202511/*"
Action   = ["s3:GetObject", "s3:GetObjectVersion"]

# Statement 2: List Access (no conditions needed)
Resource = "arn:aws:s3:eu-west-2:ACCOUNT:accesspoint/snowflakeap-snowflake-ap"
Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
```

**Design principles:**
- ✅ Access Point resources only (no direct bucket ARNs)
- ✅ Path restriction in Resource (202511/*)
- ✅ No conditions needed (simplicity)
- ✅ No direct bucket access possible

### Layer 3: Access Point Policy
**Purpose**: Explicit allow for specific IAM role only

```hcl
# Statement 1: Object Access
Principal = { AWS = "arn:aws:iam::ACCOUNT:role/snowflakeap-role" }
Action    = ["s3:GetObject", "s3:GetObjectVersion"]
Resource  = "${access_point_arn}/object/*"

# Statement 2: List Access
Principal = { AWS = "arn:aws:iam::ACCOUNT:role/snowflakeap-role" }
Action    = "s3:ListBucket"
Resource  = access_point_arn
```

**Design principles:**
- ✅ **Explicit principal** - No `Principal: "*"` with conditions
- ✅ **No wildcards** - Direct ARN specification
- ✅ **Easy to audit** - Clear who has access
- ✅ **Hard to misconfigure** - Simple Allow statements

### Layer 4: Bucket Policy
**Purpose**: Delegate all access control to Access Point

```hcl
Principal = "*"
Action    = "s3:*"
Resource  = [bucket_arn, "${bucket_arn}/*"]
Condition = {
  StringEquals = {
    "s3:DataAccessPointAccount" = "ACCOUNT_ID"
  }
}
```

**What it enforces:**
- ✅ All bucket access must go through Access Point
- ✅ Only Access Points from same account allowed
- ✅ No direct bucket access from any principal

## What Snowflake CAN Access
- ✅ Files in `s3://bucket/202511/` via Access Point
- ✅ List objects via Access Point
- ✅ Read objects via Access Point

## What Snowflake CANNOT Access
- ❌ Files in `s3://bucket/secret/` (blocked by Storage Integration)
- ❌ Files in any other prefix (blocked by IAM policy path)
- ❌ Direct bucket access (blocked by IAM policy + bucket policy)
- ❌ Root level objects (blocked by IAM policy path)

## Testing Access Restrictions

### Test 1: Successful Data Load
```bash
./run_worksheet.sh load_data_worksheet.sql
```
**Expected:** 5 rows loaded from `202511/sample_users.parquet` ✅

### Test 2: Secret Directory Blocked
```bash
./run_worksheet.sh test_secret_access.sql
```
**Expected:** `Location 's3://.../secret/' is not allowed by integration` ❌

### Test 3: Manual Verification
```sql
USE DATABASE snowflakeap_DB;
USE SCHEMA snowflakeap_SC;

-- Should work
LIST @snowflakeap_S3_STAGE;

-- Should fail (Storage Integration blocks it)
CREATE STAGE TEST_BAD
  STORAGE_INTEGRATION = snowflakeap_S3_INTEGRATION
  URL = 's3://<alias>/secret/';
```

## Security Principles Applied

### 1. Least Privilege
- Snowflake IAM role has minimum permissions
- Only GetObject, GetObjectVersion, ListBucket, GetBucketLocation
- Only on Access Point, never direct bucket

### 2. Defense in Depth
Four independent security layers must all allow access:
1. Storage Integration path restriction
2. IAM role Access Point-only permissions
3. Access Point explicit principal allow
4. Bucket policy Access Point delegation

### 3. Explicit Principals (No Wildcards)
- Access Point policy uses explicit IAM role ARN
- No `Principal: "*"` with StringNotEquals conditions
- Simpler, easier to audit

### 4. Path-Based Restriction
- IAM policy Resource includes `/202511/*` path
- No wildcards in object paths
- Enforced at multiple layers

### 5. No Direct Bucket Access
- IAM policy only grants Access Point permissions
- Bucket policy requires s3:DataAccessPointAccount
- Impossible to bypass Access Point

## Key Differences from Common Approaches

### What We DON'T Do:
- ❌ Grant both bucket and Access Point permissions (IAM role)
- ❌ Use `Principal: "*"` with `StringNotEquals` conditions (Access Point)
- ❌ Rely solely on prefix conditions
- ❌ Use overly complex nested conditions

### What We DO:
- ✅ Access Point-only IAM permissions
- ✅ Explicit principal ARNs (no wildcards)
- ✅ Path restrictions in Resource strings
- ✅ Simple, auditable policies

## Outputs

After running `terraform apply`:
```bash
access_point_alias   = "snowflakeap-snowflak-<unique-id>-s3alias"
access_point_arn     = "arn:aws:s3:eu-west-2:ACCOUNT:accesspoint/snowflakeap-snowflake-ap"
bucket_name          = "snowflakeap-2025-eu-west-2"
snowflake_role_arn   = "arn:aws:iam::ACCOUNT:role/snowflakeap-role"
```

## Verification Checklist

- [ ] `make` completes successfully
- [ ] `./run_worksheet.sh load_data_worksheet.sql` loads 5 rows
- [ ] `./run_worksheet.sh test_secret_access.sql` blocks secret/ access
- [ ] Snowflake stage lists files: `LIST @snowflakeap_S3_STAGE`
- [ ] IAM policy has no direct bucket ARNs
- [ ] Access Point policy uses explicit principal (no wildcards)
- [ ] Bucket policy delegates to Access Point

## References
- [AWS S3 Access Points](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-points.html)
- [Snowflake Storage Integration](https://docs.snowflake.com/en/user-guide/data-load-s3-config-storage-integration)
- [Blog: S3 Access Points](https://dabase.com/blog/2025/s3-access-points/)
