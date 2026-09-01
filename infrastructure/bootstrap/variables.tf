variable "aws_region" {
  description = "AWS region to create the state bucket in."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short project name used for tagging and naming."
  type        = string
  default     = "devops-portfolio"
}

variable "state_bucket_name" {
  description = "Globally-unique S3 bucket name for Terraform remote state. CUSTOMIZE THIS."
  type        = string
  # Example: "devops-portfolio-tfstate-123456789012"
}
