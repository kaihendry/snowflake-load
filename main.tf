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

// add s3 permissions to the role
resource "aws_iam_role_policy" "snowflake_access_policy" {
  name = "${local.project}-${local.snowflake_iam_role}-policy"
  role = aws_iam_role.snowflake_access_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.example.arn,
          "${aws_s3_bucket.example.arn}/*"
        ]
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
// Create storage integration first without IAM role ARN
resource "snowflake_storage_integration" "s3_integration" {
  name                 = "${local.project}_S3_INTEGRATION"
  storage_aws_role_arn = local.precalculated_snowflake_role_arn
  storage_provider     = "S3"
  enabled              = true
  storage_allowed_locations = [
    "s3://${aws_s3_bucket.example.bucket}/"
  ]
}
