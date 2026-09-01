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
  default = "prod"
}

variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "vpc_cidr" {
  type    = string
  default = "10.1.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.1.0.0/24", "10.1.1.0/24"]
}

variable "app_subnet_cidrs" {
  type    = list(string)
  default = ["10.1.10.0/24", "10.1.11.0/24"]
}

variable "db_subnet_cidrs" {
  type    = list(string)
  default = ["10.1.20.0/24", "10.1.21.0/24"]
}

variable "app_container_port" {
  type    = number
  default = 3000
}

variable "image_tag" {
  description = "Git commit SHA of the image to deploy. CI/CD passes this via -var after it has been validated in staging and approved for production."
  type        = string
  default     = "bootstrap-placeholder"
}

variable "task_cpu" {
  type    = number
  default = 512
}

variable "task_memory" {
  type    = number
  default = 1024
}

variable "desired_count" {
  type    = number
  default = 2
}

variable "min_capacity" {
  type    = number
  default = 2
}

variable "max_capacity" {
  type    = number
  default = 6
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.small"
}

variable "db_multi_az" {
  description = "Production runs Multi-AZ RDS for automatic failover."
  type        = bool
  default     = true
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
  type    = string
  default = ""
}

variable "log_retention_days" {
  type    = number
  default = 30
}
