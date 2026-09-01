output "state_bucket_name" {
  description = "Name of the S3 bucket to reference in envs/*/backend.tf"
  value       = aws_s3_bucket.terraform_state.id
}

output "state_bucket_arn" {
  value = aws_s3_bucket.terraform_state.arn
}

output "kms_key_arn" {
  description = "KMS key ARN used to encrypt Terraform state"
  value       = aws_kms_key.terraform_state.arn
}
