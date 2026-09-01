terraform {
  backend "s3" {
    bucket       = "devops-portfolio-tfstate-REPLACE_WITH_ACCOUNT_ID"
    key          = "envs/prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
