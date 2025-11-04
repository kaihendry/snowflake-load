terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    snowflake = {
      source = "snowflakedb/snowflake"
    }
  }
}

locals {
  project                          = "snowflakeap"
  snowflake_iam_role               = "role"
  precalculated_snowflake_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${join("-", [local.project, local.snowflake_iam_role])}"
}

provider "aws" {
  region = "eu-west-2"
  default_tags {
    tags = {
      Owner   = "kaihendry"
      Project = local.project
    }
  }
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "example" {
  bucket = format(
    "%s-%s-%s",
    local.project,
    "2025",
    data.aws_region.current.id
  )
}

# S3 Access Point restricted to 202511/ prefix only
resource "aws_s3_access_point" "snowflake_access_point" {
  bucket = aws_s3_bucket.example.id
  name   = "${local.project}-snowflake-ap"

  public_access_block_configuration {
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
  }
}

# Access Point Policy - STRICT DENY-based approach
# Uses 3 DENY statements with negative conditions for defense-in-depth
# All conditions must pass (logical AND) for access to be granted
# Trade-off: More complex than simple role-level lock (see SECURITY.md)
resource "aws_s3control_access_point_policy" "snowflake_access_point_policy" {
  access_point_arn = aws_s3_access_point.snowflake_access_point.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # 1. Deny blocked object actions (write and delete not allowed)
      {
        Sid       = "DenyBlockedObjectActions"
        Effect    = "Deny"
        Principal = "*"
        Action = [
          "s3:PutObject",
          "s3:PutObjectTagging",
          "s3:PutObjectVersionTagging",
          "s3:DeleteObject",
          "s3:DeleteObjectTagging",
          "s3:DeleteObjectVersion",
          "s3:DeleteObjectVersionTagging"
        ]
        Resource = "${aws_s3_access_point.snowflake_access_point.arn}/object/*"
      },
      # 2. Deny allowed actions if NOT from the authorized principal
      {
        Sid       = "DenyAllowedActionsIfNotPrincipal"
        Effect    = "Deny"
        Principal = "*"
        Action = [
          "s3:ListBucket",
          "s3:ListBucketVersions",
          "s3:GetObject",
          "s3:GetObjectTagging",
          "s3:GetObjectVersion",
          "s3:GetObjectVersionTagging"
        ]
        Resource = [
          aws_s3_access_point.snowflake_access_point.arn,
          "${aws_s3_access_point.snowflake_access_point.arn}/object/*"
        ]
        Condition = {
          StringNotEquals = {
            "aws:PrincipalArn" = aws_iam_role.snowflake_access_role.arn
          }
        }
      },
      # 3. Deny read actions if NOT within the 202511/ prefix
      {
        Sid       = "DenyReadIfNotPrefix"
        Effect    = "Deny"
        Principal = "*"
        Action = [
          "s3:GetObject",
          "s3:GetObjectTagging",
          "s3:GetObjectVersion",
          "s3:GetObjectVersionTagging"
        ]
        NotResource = [
          "${aws_s3_access_point.snowflake_access_point.arn}/object/202511/*"
        ]
      }
    ]
  })
}

# Bucket policy - delegate access control to Access Point
# Access through Access Point only, no direct bucket access
resource "aws_s3_bucket_policy" "delegate_to_access_point" {
  bucket = aws_s3_bucket.example.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DelegateToAccessPoint"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.example.arn,
          "${aws_s3_bucket.example.arn}/*"
        ]
        Condition = {
          StringEquals = {
            "s3:DataAccessPointAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

// Create Snowflake IAM role based on the results of storage integration
resource "aws_iam_role" "snowflake_access_role" {
  name = join("-", [local.project, local.snowflake_iam_role])

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          AWS = snowflake_storage_integration.s3_integration.storage_aws_iam_user_arn
        }
        Condition = {
          StringEquals = {
            "sts:ExternalId" = snowflake_storage_integration.s3_integration.storage_aws_external_id
          }
        }
      }
    ]
  })
  depends_on = [snowflake_storage_integration.s3_integration]
}

// IAM role policy - ONLY allows Access Point access (no direct bucket access)
// This enforces that all S3 operations must go through the Access Point
resource "aws_iam_role_policy" "snowflake_access_policy" {
  name = "${local.project}-${local.snowflake_iam_role}-policy"
  role = aws_iam_role.snowflake_access_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAccessPointObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "${aws_s3_access_point.snowflake_access_point.arn}/object/202511/*"
      },
      {
        Sid    = "AllowAccessPointListAccess"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = aws_s3_access_point.snowflake_access_point.arn
      }
    ]
  })
}

locals {
  organization_name = "xbjfxng"
  account_name      = "qm18685"
  private_key_path  = "keys/snowflake_tf_snow_key.p8"
}

provider "snowflake" {
  organization_name        = local.organization_name
  account_name             = local.account_name
  user                     = "TERRAFORM_SVC"
  role                     = "ACCOUNTADMIN"
  authenticator            = "SNOWFLAKE_JWT"
  private_key              = file(local.private_key_path)
  preview_features_enabled = ["snowflake_storage_integration_resource", "snowflake_stage_resource"]
}

resource "snowflake_database" "tf_db" {
  name         = "${local.project}_DB"
  is_transient = false
}

resource "snowflake_warehouse" "tf_warehouse" {
  name                      = "${local.project}_WH"
  warehouse_type            = "STANDARD"
  warehouse_size            = "SMALL"
  max_cluster_count         = 1
  min_cluster_count         = 1
  auto_suspend              = 60
  auto_resume               = true
  enable_query_acceleration = false
  initially_suspended       = true
}

# Create a new schema in the DB
resource "snowflake_schema" "tf_db_tf_schema" {
  name                = "${local.project}_SC"
  database            = snowflake_database.tf_db.name
  with_managed_access = false
}

// https://registry.terraform.io/providers/snowflakedb/snowflake/latest/docs/resources/storage_integration
// Create storage integration using Access Point ARN
resource "snowflake_storage_integration" "s3_integration" {
  name                    = "${local.project}_S3_INTEGRATION"
  storage_aws_role_arn    = local.precalculated_snowflake_role_arn
  storage_provider        = "S3"
  enabled                 = true
  storage_aws_external_id = "foobar"
  storage_allowed_locations = [
    "s3://${aws_s3_access_point.snowflake_access_point.alias}/202511/"
  ]
}

# Create stage using snowflake_execute since provider doesn't support aws_access_point_arn
# We need to create the stage directly with CREATE OR REPLACE STAGE SQL
resource "snowflake_execute" "create_stage_with_access_point" {
  execute = "CREATE OR REPLACE STAGE \"${snowflake_database.tf_db.name}\".\"${snowflake_schema.tf_db_tf_schema.name}\".\"${local.project}_S3_STAGE\" STORAGE_INTEGRATION = \"${snowflake_storage_integration.s3_integration.name}\" URL = 's3://${aws_s3_access_point.snowflake_access_point.alias}/202511/' AWS_ACCESS_POINT_ARN = '${aws_s3_access_point.snowflake_access_point.arn}' DIRECTORY = (ENABLE = TRUE)"

  revert = "DROP STAGE IF EXISTS \"${snowflake_database.tf_db.name}\".\"${snowflake_schema.tf_db_tf_schema.name}\".\"${local.project}_S3_STAGE\""

  depends_on = [snowflake_storage_integration.s3_integration, snowflake_schema.tf_db_tf_schema]
}

# Outputs
output "access_point_arn" {
  description = "ARN of the S3 Access Point"
  value       = aws_s3_access_point.snowflake_access_point.arn
}

output "access_point_alias" {
  description = "Alias of the S3 Access Point (use this for S3 operations)"
  value       = aws_s3_access_point.snowflake_access_point.alias
}

output "bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.example.bucket
}

output "snowflake_role_arn" {
  description = "ARN of the IAM role used by Snowflake"
  value       = aws_iam_role.snowflake_access_role.arn
}
