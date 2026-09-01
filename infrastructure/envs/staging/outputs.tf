output "alb_dns_name" {
  description = "Public URL of the staging application (http://<this>)"
  value       = module.alb.alb_dns_name
}

output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "ecs_cluster_name" {
  value = module.ecs.cluster_name
}

output "ecs_service_name" {
  value = module.ecs.service_name
}

output "task_definition_family" {
  value = module.ecs.task_definition_family
}

output "github_actions_role_arn" {
  description = "Set as the AWS_DEPLOY_ROLE_ARN GitHub Actions variable for the staging environment"
  value       = module.iam.github_actions_role_arn
}

output "oidc_provider_arn" {
  description = "Pass to envs/prod's github_oidc_provider_arn variable"
  value       = module.iam.oidc_provider_arn
}

output "db_address" {
  value = module.rds.db_address
}

output "log_group_name" {
  value = module.cloudwatch.log_group_name
}

output "infrastructure_dashboard_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${module.cloudwatch.infrastructure_dashboard_name}"
}

output "application_dashboard_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${module.cloudwatch.application_dashboard_name}"
}
