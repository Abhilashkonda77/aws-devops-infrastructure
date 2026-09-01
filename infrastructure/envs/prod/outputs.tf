output "alb_dns_name" {
  description = "Public URL of the production application (http://<this>)"
  value       = module.alb.alb_dns_name
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
  description = "Set as the AWS_DEPLOY_ROLE_ARN GitHub Actions variable for the production environment"
  value       = module.iam.github_actions_role_arn
}

output "db_address" {
  value = module.rds.db_address
}

output "infrastructure_dashboard_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${module.cloudwatch.infrastructure_dashboard_name}"
}

output "application_dashboard_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${module.cloudwatch.application_dashboard_name}"
}
