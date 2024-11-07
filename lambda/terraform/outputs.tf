
output "function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.monitoring.function_name
}

output "function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.monitoring.arn
}

output "function_role_arn" {
  description = "ARN of the Lambda function's IAM role"
  value       = aws_iam_role.lambda_role.arn
}

output "function_role_name" {
  description = "Name of the Lambda function's IAM role"
  value       = aws_iam_role.lambda_role.name
}

output "metrics_bucket_name" {
  description = "Name of the S3 bucket storing metrics"
  value       = aws_s3_bucket.metrics.id
}

output "metrics_bucket_arn" {
  description = "ARN of the S3 bucket storing metrics"
  value       = aws_s3_bucket.metrics.arn
}

output "log_group_name" {
  description = "Name of the CloudWatch Log Group"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "function_url" {
  description = "Function URL (if enabled)"
  value       = try(aws_lambda_function_url.function_url[0].function_url, null)
}

output "cloudwatch_event_rule_arn" {
  description = "ARN of the CloudWatch Event rule"
  value       = aws_cloudwatch_event_rule.schedule.arn
}