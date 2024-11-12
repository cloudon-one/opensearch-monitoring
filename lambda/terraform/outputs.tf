output "opensearch_endpoint" {
  value = aws_opensearch_domain.monitoring.endpoint
}

output "opensearch_dashboard_endpoint" {
  value = aws_opensearch_domain.monitoring.dashboard_endpoint
}

output "monitoring_role_arn" {
  description = "ARN of the monitoring role template"
  value       = aws_iam_role.monitoring_template.arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda monitoring role"
  value       = aws_iam_role.lambda_monitoring.arn
}

output "monitoring_role_name" {
  description = "Name of the monitoring role to be created in monitored accounts"
  value       = var.monitoring_role_name
}
