variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "ecr_repository_arn" {
  type = string
}

variable "db_secret_arn" {
  description = "Secrets Manager ARN for the RDS master password."
  type        = string
}

variable "log_group_arn" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
