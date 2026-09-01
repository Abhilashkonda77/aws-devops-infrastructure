variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "azs" {
  description = "Exactly two availability zones."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "app_subnet_cidrs" {
  description = "Private application subnet CIDRs (ECS Fargate)."
  type        = list(string)
}

variable "db_subnet_cidrs" {
  description = "Private database subnet CIDRs (RDS)."
  type        = list(string)
}

variable "app_container_port" {
  description = "Port the application container listens on; ECS security group allows this port from the ALB only."
  type        = number
  default     = 3000
}

variable "tags" {
  type    = map(string)
  default = {}
}
