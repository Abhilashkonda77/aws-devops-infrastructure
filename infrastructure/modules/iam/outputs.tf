output "task_execution_role_arn" {
  value = aws_iam_role.task_execution.arn
}

output "task_role_arn" {
  value = aws_iam_role.task.arn
}

output "github_actions_role_arn" {
  description = "Put this ARN into the GitHub Actions workflow / repo variable AWS_DEPLOY_ROLE_ARN"
  value       = aws_iam_role.github_actions.arn
}

output "oidc_provider_arn" {
  description = "GitHub OIDC provider ARN. Pass into other environments' github_oidc_provider_arn when create_oidc_provider = false there."
  value       = local.oidc_provider_arn
}
