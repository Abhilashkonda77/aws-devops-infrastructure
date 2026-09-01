terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Reads staging's outputs (shared ECR repo, GitHub OIDC provider) so they
# are not duplicated. Requires staging to have been applied first, and
# requires read access to the same state bucket.
data "terraform_remote_state" "staging" {
  backend = "s3"
  config = {
    bucket = "devops-portfolio-tfstate-REPLACE_WITH_ACCOUNT_ID"
    key    = "envs/staging/terraform.tfstate"
    region = var.aws_region
  }
}
