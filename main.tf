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

locals {
  organization_name = "xbjfxng"
  account_name      = "qm18685"
  private_key_path  = "keys/snowflake_tf_snow_key.p8"
}

provider "snowflake" {
  organization_name = local.organization_name
  account_name      = local.account_name
  user              = "TERRAFORM_SVC"
  role              = "SYSADMIN"
  authenticator     = "SNOWFLAKE_JWT"
  private_key       = file(local.private_key_path)
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
