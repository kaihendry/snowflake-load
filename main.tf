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
  project = "snowflakeap"
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

resource "aws_s3_bucket" "example" {
  bucket = format(
    "%s-%s-%s",
    local.project,
    "2025",
    data.aws_region.current.id
  )
}

// create a IAM role that can read the bucket
resource "aws_iam_role" "snowflake_access_role" {
  name = "${local.project}-snowflake-access-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Deny"
        Principal = {
          AWS = "*"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

// add s3 permissions to the role
resource "aws_iam_role_policy" "snowflake_access_policy" {
  name = "${local.project}-snowflake-access-policy"
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
resource "snowflake_storage_integration" "s3_integration" {
  depends_on              = [aws_iam_role.snowflake_access_role]
  name                    = "${local.project}_S3_INTEGRATION"
  storage_provider        = "S3"
  enabled                 = true
  storage_aws_external_id = "testing-external-id-12345"
  storage_aws_role_arn    = aws_iam_role.snowflake_access_role.arn
  storage_allowed_locations = [
    "s3://${aws_s3_bucket.example.bucket}/"
  ]
}

# To avoid a Terraform 'Cycle Error', we need to update the AWS role with the correct trusted relationship,
# using the new snowflake arns we received from the integration
resource "null_resource" "update_iam_role" {
  depends_on = [snowflake_storage_integration.s3_integration, aws_iam_role.snowflake_access_role]
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = <<EOT
      aws iam update-assume-role-policy --role-name ${aws_iam_role.snowflake_access_role.name} --policy-document '{
        "Version": "2012-10-17",
        "Statement": [
          {
            "Effect": "Allow",
            "Principal": {
              "AWS": "${snowflake_storage_integration.s3_integration.storage_aws_iam_user_arn}"
            },
            "Action": "sts:AssumeRole",
            "Condition": {
              "StringEquals": {
                "sts:ExternalId": "${snowflake_storage_integration.s3_integration.storage_aws_external_id}"
              }
            }
          }
        ]
      }'
    EOT
  }
}
