# Remote state in the S3 bucket created by infrastructure/bootstrap.
#
# `use_lockfile = true` enables Terraform's native S3 state locking
# (via S3 conditional writes), available in Terraform >= 1.10. This
# replaces the older pattern of a separate DynamoDB lock table — no
# DynamoDB resource is created or required by this project.
#
# CUSTOMIZE: bucket, region, and (optionally) key.
terraform {
  backend "s3" {
    bucket       = "devops-portfolio-tfstate-REPLACE_WITH_ACCOUNT_ID"
    key          = "envs/staging/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
