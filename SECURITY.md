# S3 Access Point Security Implementation

## Overview
This project uses **S3 Access Points** to restrict Snowflake's access to only the `202511/` prefix in the S3 bucket. This ensures that Snowflake cannot access any other data in the bucket, including the `secret/` directory or any other prefixes.

## Architecture

### Components
1. **S3 Bucket**: `snowflakeap-2025-eu-west-2`
2. **S3 Access Point**: `snowflakeap-snowflake-ap` - restricted to `202511/` prefix only
3. **IAM Role**: `snowflakeap-role` - can only access data through the Access Point
4. **Snowflake Storage Integration**: Configured to use the Access Point alias
5. **Snowflake Stage**: Points to the Access Point URL

### Security Layers

#### Layer 1: Access Point Policy
The Access Point policy (`aws_s3control_access_point_policy`) explicitly restricts access to:
- **GetObject/GetObjectVersion**: Only on `202511/*` objects
- **ListBucket**: Only with prefix condition for `202511/*`

```hcl
Resource = "${access_point_arn}/object/202511/*"
Condition = {
  StringLike = {
    "s3:prefix" = ["202511/*"]
  }
}
```

#### Layer 2: IAM Role Policy
The IAM role policy (`aws_iam_role_policy`) mirrors the Access Point restrictions:
- Grants permissions only to the Access Point ARN, not the bucket ARN
- Restricts to `202511/*` prefix only
- No direct bucket access permissions

#### Layer 3: Bucket Policy
The bucket policy (`aws_s3_bucket_policy`) enforces Access Point usage:
- **Denies** all S3 operations from the Snowflake role on the bucket
- **Exception**: Only allows access when coming through the specific Access Point
- Uses condition: `s3:DataAccessPointArn` must equal the Access Point ARN

```hcl
Effect = "Deny"
Condition = {
  StringNotEquals = {
    "s3:DataAccessPointArn" = aws_s3_access_point.snowflake_access_point.arn
  }
}
```

## What Snowflake CAN Access
- ✅ Files in `s3://snowflakeap-2025-eu-west-2/202511/`
- ✅ List objects with prefix `202511/`

## What Snowflake CANNOT Access
- ❌ Files in `s3://snowflakeap-2025-eu-west-2/secret/`
- ❌ Files in any other prefix (e.g., `202510/`, `202512/`, etc.)
- ❌ Root level objects in the bucket
- ❌ Bucket metadata or configuration
- ❌ Direct bucket access (must use Access Point)

## Testing Access Restrictions

### Test 1: Verify Access to 202511/
```bash
# Upload test file
aws s3 cp test.txt s3://snowflakeap-2025-eu-west-2/202511/test.txt

# In Snowflake
LIST @snowflakeap_S3_STAGE;
-- Should show files in 202511/
```

### Test 2: Verify NO Access to secret/
```bash
# Upload to secret directory
aws s3 cp secret.txt s3://snowflakeap-2025-eu-west-2/secret/secret.txt

# Try to access from Snowflake using direct bucket path (will fail)
LIST 's3://snowflakeap-2025-eu-west-2/secret/';
-- Should fail with access denied
```

### Test 3: Verify NO Access to other prefixes
```bash
# Upload to different prefix
aws s3 cp test.txt s3://snowflakeap-2025-eu-west-2/202512/test.txt

# Try to access from Snowflake (will fail)
LIST 's3://snowflakeap-2025-eu-west-2/202512/';
-- Should fail with access denied
```

## Deployment Notes

1. **First time deployment**: Run `terraform apply` to create all resources
2. **Access Point Alias**: The Access Point creates a unique alias (available in outputs)
3. **Snowflake Configuration**: The storage integration and stage automatically use the Access Point
4. **File Uploads**: Use the Makefile `make upload` command which uploads to `202511/`

## Key Outputs

After running `terraform apply`, you'll see:
- `access_point_arn`: The ARN of the Access Point
- `access_point_alias`: The alias to use for S3 operations (auto-used by Snowflake)
- `bucket_name`: The underlying S3 bucket name
- `snowflake_role_arn`: The IAM role ARN used by Snowflake

## Security Principles Applied

1. **Least Privilege**: Snowflake only has access to exactly what it needs
2. **Defense in Depth**: Multiple layers of security (Access Point, IAM, Bucket Policy)
3. **Explicit Deny**: Bucket policy explicitly denies direct bucket access
4. **Prefix Isolation**: Access Point enforces prefix-level isolation
5. **Audit Trail**: All access is logged via CloudTrail with Access Point ARN

## References
- [AWS S3 Access Points](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-points.html)
- [Snowflake Storage Integration](https://docs.snowflake.com/en/user-guide/data-load-s3-config-storage-integration)
