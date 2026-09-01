output "log_group_name" {
  value = aws_cloudwatch_log_group.app.name
}

output "log_group_arn" {
  value = aws_cloudwatch_log_group.app.arn
}

output "sns_topic_arn" {
  value = aws_sns_topic.alarms.arn
}

output "infrastructure_dashboard_name" {
  value = aws_cloudwatch_dashboard.infrastructure.dashboard_name
}

output "application_dashboard_name" {
  value = aws_cloudwatch_dashboard.application.dashboard_name
}
