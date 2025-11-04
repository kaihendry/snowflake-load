# S3 Access Point Security Implementation

## Overview
This project uses **S3 Access Points** with a **strict DENY-based security model** to restrict Snowflake's access to only the `202511/` prefix in the S3 bucket. The design uses multiple DENY statements for defense-in-depth at the Access Point level.

**⚠️ Trade-off Warning**: This approach uses 3 DENY statements which adds significant complexity. A simpler alternative exists (see "Trade-offs" section below).

---

## Access Point Policy: ALLOW vs DENY-based Approach

### Summary of Changes

Changed from an **explicit ALLOW-based policy** to a **strict DENY-based policy** with three DENY statements.

### Old Approach: ALLOW-based Policy

```json
{
  "Statement": [
    {
      "Sid": "AllowObjectAccess",
      "Effect": "Allow",
      "Principal": {"AWS": "arn:aws:iam::xxx:role/snowflake-role"},
      "Action": ["s3:GetObject", "s3:GetObjectVersion"],
      "Resource": "arn:aws:s3:region:account:accesspoint/ap-name/object/*"
    },
    {
      "Sid": "AllowListAccess",
      "Effect": "Allow",
      "Principal": {"AWS": "arn:aws:iam::xxx:role/snowflake-role"},
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:region:account:accesspoint/ap-name"
    }
  ]
}
```

**Problems with ALLOW-based:**
- **Additive security**: Other policies can grant additional permissions
- **Single layer**: If this policy is bypassed, there's no fallback
- **Easier to accidentally over-grant**: Missing conditions = broader access
- **Prefix restrictions only in IAM role**: Not enforced at the Access Point level

### New Approach: DENY-based Policy

```json
{
  "Statement": [
    {
      "Sid": "DenyBlockedObjectActions",
      "Effect": "Deny",
      "Principal": "*",
      "Action": ["s3:PutObject", "s3:DeleteObject", ...],
      "Resource": "arn:aws:s3:region:account:accesspoint/ap-name/object/*"
    },
    {
      "Sid": "DenyAllowedActionsIfNotPrincipal",
      "Effect": "Deny",
      "Principal": "*",
      "Action": ["s3:GetObject", "s3:ListBucket", ...],
      "Resource": [...],
      "Condition": {
        "StringNotEquals": {"aws:PrincipalArn": "arn:aws:iam::xxx:role/snowflake-role"}
      }
    },
    {
      "Sid": "DenyReadIfNotPrefix",
      "Effect": "Deny",
      "Principal": "*",
      "Action": ["s3:GetObject", ...],
      "NotResource": ["arn:aws:s3:region:account:accesspoint/ap-name/object/202511/*"]
    }
  ]
}
```

**Benefits of DENY-based:**

1. **Defense in Depth**
   - Multiple DENY statements that ALL must pass (logical AND)
   - If any condition fails, access is denied
   - Cannot be overridden by other ALLOW policies

2. **Explicit Blocklist**
   - `DenyBlockedObjectActions`: Explicitly denies write/delete operations
   - Acts as a safety net preventing ANY write or delete through the AP

3. **Negative Conditions (More Restrictive)**
   - `StringNotEquals`: "Deny if NOT this principal" is stronger than "Allow if this principal"
   - Forces ALL other principals to be explicitly denied
   - No room for ambiguity or accidental grants

4. **NotResource Pattern**
   - `DenyReadIfNotPrefix`: "Deny read if NOT in 202511/ prefix"
   - Enforces prefix restriction at the Access Point level (not just IAM)
   - More restrictive than positive Resource matching

5. **Principle of Least Privilege**
   - Default state is DENY
   - Access is only granted if you satisfy ALL negative conditions
   - Harder to accidentally bypass

### AWS Policy Evaluation Order

AWS evaluates policies in this order:
1. **Explicit DENY** (highest priority - cannot be overridden)
2. **Explicit ALLOW**
3. **Implicit DENY** (default)

The DENY-based approach leverages #1 to create an unbreakable security boundary.

### Example Scenario Comparison

**With ALLOW-based policy:**
- IAM role has `s3:GetObject` on bucket (via bucket policy)
- Access Point policy allows `s3:GetObject` for role
- ✅ Access granted
- ⚠️ If another policy grants broader permissions, they stack

**With DENY-based policy:**
- Three layers of DENY must be passed:
  1. ❌ Is this a blocked action? → No (read is allowed)
  2. ❌ Is this NOT the authorized principal? → No (it is the authorized principal)
  3. ❌ Is this NOT in the 202511/ prefix? → No (it is in 202511/)
- ✅ All DENY conditions passed, access granted via IAM role policy
- 🔒 Even if another policy grants broader permissions, the DENYs override them

### Key Differences Table

| Aspect | ALLOW-based | DENY-based |
|--------|-------------|------------|
| **Default state** | Implicit deny | Explicit deny |
| **Security model** | Permissive | Restrictive |
| **Policy stacking** | Additive (can expand) | Subtractive (cannot override) |
| **Prefix enforcement** | IAM only | Access Point + IAM |
| **Bypass risk** | Higher | Lower |
| **Complexity** | Simple | More complex |
| **Best practice** | ❌ Not recommended | ✅ Recommended |

### Trade-offs: 3 DENY Statements vs Simple Role-Level Lock

The current implementation uses **3 DENY statements** for maximum defense-in-depth. However, there's a **simpler alternative** that may be more practical.

#### Current Approach (3 DENY Statements)
✅ **Pros:**
- Explicit blocklist of write/delete actions at Access Point level
- Prefix restriction enforced at Access Point (not just IAM)
- Multiple layers that ALL must pass (logical AND)

❌ **Cons:**
- **Stupidly complex** - Hard to understand and audit
- **Easy to misconfigure** - More statements = more ways to break it
- **Duplicates IAM logic** - Prefix restrictions already in IAM policy
- **Maintenance burden** - Changes require updating multiple statements

#### Simpler Alternative: Single Role-Level Lock ([see blog](https://dabase.com/blog/2025/s3-access-points/#role-level-only-policy))

```json
{
  "Statement": [
    {
      "Sid": "LockAccessPointToOneRole",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:REGION:ACCOUNT:accesspoint/AP_NAME",
        "arn:aws:s3:REGION:ACCOUNT:accesspoint/AP_NAME/object/*"
      ],
      "Condition": {
        "StringNotEquals": {
          "aws:PrincipalArn": "arn:aws:iam::ACCOUNT:role/ROLE_NAME"
        }
      }
    }
  ]
}
```

✅ **Pros:**
- **Tiny, easy to reason about** - One statement, clear intent
- **Hard to misconfigure** - Minimal surface area for errors
- **Delegates to IAM** - Let IAM identity policies do the heavy lifting
- **Universal blocking** - No cross-account backdoors, no anonymous access

❌ **Cons:**
- No prefix enforcement at Access Point level (relies on IAM)
- No explicit write/delete blocklist at Access Point level (relies on IAM)

#### Recommendation

**For most use cases**: Use the **simple role-level lock**. It's easier to maintain, harder to misconfigure, and leverages IAM's strengths.

**Use 3 DENY statements only if**:
- You need defense-in-depth at the Access Point layer itself
- You don't trust IAM policy governance to remain strict
- You need prefix restrictions that cannot be bypassed by future IAM changes

This project uses the 3 DENY approach as an **example** of the complex pattern, but the simple approach is often better.

---

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

### Layer 3: Access Point Policy (DENY-based)
**Purpose**: Strict DENY-based policy with defense-in-depth (3 DENY statements)

```hcl
# Statement 1: Deny blocked object actions (write and delete not allowed)
Effect    = "Deny"
Principal = "*"
Action    = ["s3:PutObject", "s3:DeleteObject", ...]
Resource  = "${access_point_arn}/object/*"

# Statement 2: Deny allowed actions if NOT from authorized principal
Effect    = "Deny"
Principal = "*"
Action    = ["s3:ListBucket", "s3:GetObject", ...]
Resource  = [access_point_arn, "${access_point_arn}/object/*"]
Condition = {
  StringNotEquals = {
    "aws:PrincipalArn" = "arn:aws:iam::ACCOUNT:role/snowflakeap-role"
  }
}

# Statement 3: Deny read actions if NOT within 202511/ prefix
Effect      = "Deny"
Principal   = "*"
Action      = ["s3:GetObject", "s3:GetObjectVersion", ...]
NotResource = ["${access_point_arn}/object/202511/*"]
```

**Design principles:**
- ✅ **Multiple DENY layers** - All must pass (logical AND)
- ✅ **Negative conditions** - StringNotEquals is more restrictive
- ✅ **NotResource pattern** - Enforces prefix at Access Point level
- ✅ **Cannot be overridden** - DENY takes highest precedence
- ✅ **Defense-in-depth** - Three independent security checks

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
3. Access Point DENY-based policy (3 DENY statements that ALL must pass)
4. Bucket policy Access Point delegation

The Access Point DENY-based policy adds additional sub-layers:
- Layer 3a: Deny blocked actions (write/delete)
- Layer 3b: Deny if NOT authorized principal
- Layer 3c: Deny if NOT within 202511/ prefix

### 3. DENY-based Policy with Negative Conditions
- Access Point policy uses `Principal: "*"` with `StringNotEquals` conditions
- Multiple DENY statements that ALL must pass (logical AND)
- Cannot be overridden by other ALLOW policies

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
- ❌ Use simple ALLOW-based Access Point policies
- ❌ Rely solely on IAM-level prefix conditions
- ❌ Use single-layer security

### What We DO:
- ✅ Access Point-only IAM permissions
- ✅ DENY-based Access Point policies (3 DENY statements)
- ✅ Multiple layers of DENY that ALL must pass
- ✅ Prefix restrictions at Access Point level (NotResource pattern)
- ✅ Negative conditions (StringNotEquals) for stronger security
- ✅ Unbreakable security boundaries (DENY cannot be overridden)

**Note**: While this demonstrates the complex 3-DENY approach, the [simple role-level lock](https://dabase.com/blog/2025/s3-access-points/#role-level-only-policy) is often more practical.

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
- [ ] Access Point policy uses DENY-based approach (3 DENY statements)
- [ ] Access Point policy uses `StringNotEquals` and `NotResource` patterns
- [ ] Bucket policy delegates to Access Point

## References
- [AWS S3 Access Points](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-points.html)
- [Snowflake Storage Integration](https://docs.snowflake.com/en/user-guide/data-load-s3-config-storage-integration)
- [Blog: S3 Access Points](https://dabase.com/blog/2025/s3-access-points/)
