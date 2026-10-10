terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.68"
    }
  }

  # Partial configuration: bucket, key and region come from backend.hcl
  # (see backend.hcl.example). S3-native locking, no DynamoDB table.
  backend "s3" {
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
      Repo      = "YounessAbbida/gha-n8n-aws"
    }
  }
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}
