output "opensearch_endpoint" {
  description = "OpenSearch domain endpoint"
  value       = aws_opensearch_domain.monitoring.endpoint
}

output "monitoring_function_arn" {
  description = "Monitoring Lambda function ARN"
  value       = aws_lambda_function.monitoring.arn
}

output "opensearch_dashboard_url" {
  description = "OpenSearch dashboard URL"
  value       = "https://${aws_opensearch_domain.monitoring.endpoint}/_dashboards/"
}