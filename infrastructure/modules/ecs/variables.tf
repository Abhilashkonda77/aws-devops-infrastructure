variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "app_subnet_ids" {
  type = list(string)
}

variable "ecs_tasks_security_group_id" {
  type = string
}

variable "target_group_arn" {
  type = string
}

variable "ecr_repository_url" {
  type = string
}

variable "image_tag" {
  description = "Git commit SHA (or 'bootstrap-placeholder' for the first apply before any image has been pushed)."
  type        = string
  default     = "bootstrap-placeholder"
}

variable "app_container_port" {
  type    = number
  default = 3000
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

variable "task_execution_role_arn" {
  type = string
}

variable "task_role_arn" {
  type = string
}

variable "db_address" {
  type = string
}

variable "db_port" {
  type = number
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type = string
}

variable "db_secret_arn" {
  description = "Secrets Manager ARN for the RDS-managed master password (JSON with a 'password' key)."
  type        = string
}

variable "log_group_name" {
  description = "Name of the CloudWatch log group created at the environment root (breaks an IAM<->ECS circular dependency)."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
