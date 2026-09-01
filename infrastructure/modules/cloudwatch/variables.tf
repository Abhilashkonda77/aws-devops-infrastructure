variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "ecs_cluster_name" {
  type = string
}

variable "ecs_service_name" {
  type = string
}

variable "alb_arn_suffix" {
  type = string
}

variable "target_group_arn_suffix" {
  type = string
}

variable "rds_instance_id" {
  type = string
}

variable "sns_alarm_email" {
  description = "Email address to notify on alarm. Leave empty to skip subscription creation."
  type        = string
  default     = ""
}

variable "desired_task_count" {
  type = number
}

variable "tags" {
  type    = map(string)
  default = {}
}
