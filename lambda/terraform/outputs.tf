output "opensearch_endpoint" {
  value = aws_opensearch_domain.monitoring.endpoint
}

output "opensearch_dashboard_endpoint" {
  value = aws_opensearch_domain.monitoring.dashboard_endpoint
}