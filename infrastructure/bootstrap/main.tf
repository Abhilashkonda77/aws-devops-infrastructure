# Bootstrap stack: creates the S3 bucket that will hold Terraform remote
# state for every other stack (envs/staging, envs/prod).
#
# This stack itself uses LOCAL state on purpose — it must be applied once,
# by hand, before any remote-state-backed stack can be initialized. Do not
# try to migrate this stack's own state into the bucket it creates.
#
# State locking: Terraform >= 1.10 supports native S3 locking via
# conditional writes (the `use_lockfile` backend argument), which removes
# the need for a separate DynamoDB lock table that earlier Terraform
# versions required. This project uses that native S3 locking mechanism.
# See envs/*/backend.tf for where it is enabled.

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "aws_s3_bucket" "terraform_state" {
  # Bucket names are globally unique — customize var.state_bucket_name.
  bucket = var.state_bucket_name

  # Prevent accidental deletion of the bucket holding all Terraform state.
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Project   = var.project_name
    ManagedBy = "terraform"
    Purpose   = "terraform-remote-state"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.terraform_state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "expire-old-noncurrent-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Dedicated KMS key for encrypting Terraform state at rest. Using a
# customer-managed key (instead of the default aws/s3 key) allows tighter
# key policies and auditability via CloudTrail.
resource "aws_kms_key" "terraform_state" {
  description             = "KMS key for encrypting Terraform remote state (${var.project_name})"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}

resource "aws_kms_alias" "terraform_state" {
  name          = "alias/${var.project_name}-terraform-state"
  target_key_id = aws_kms_key.terraform_state.key_id
}
