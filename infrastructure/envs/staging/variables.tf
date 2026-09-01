variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "devops-portfolio"
}

variable "environment" {
  type    = string
  default = "staging"
}

variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "app_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "db_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.20.0/24", "10.0.21.0/24"]
}

variable "app_container_port" {
  type    = number
  default = 3000
}

variable "image_tag" {
  description = "Git commit SHA of the image to deploy. CI/CD updates this via -var on each deploy; the default is only used on the very first `terraform apply` before any image exists."
  type        = string
  default     = "bootstrap-placeholder"
}

variable "task_cpu" {
  type    = number
  default = 256
}

variable "task_memory" {
  type    = number
  default = 512
}

variable "desired_count" {
  type    = number
  default = 2
}

variable "min_capacity" {
  type    = number
  default = 1
}

variable "max_capacity" {
  type    = number
  default = 4
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_multi_az" {
  type    = bool
  default = false
}

variable "github_org" {
  description = "CUSTOMIZE: your GitHub org/user name."
  type        = string
}

variable "github_repo" {
  description = "CUSTOMIZE: your GitHub repository name."
  type        = string
}

variable "sns_alarm_email" {
  description = "Optional email for CloudWatch alarm notifications."
  type        = string
  default     = ""
}

variable "log_retention_days" {
  type    = number
  default = 14
}
