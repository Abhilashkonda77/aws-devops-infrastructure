variable "project_name" {
  type = string
}

variable "max_image_count" {
  description = "How many tagged images to retain before the lifecycle policy expires the oldest."
  type        = number
  default     = 20
}

variable "tags" {
  type    = map(string)
  default = {}
}
