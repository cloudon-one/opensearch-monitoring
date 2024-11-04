output "function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.main.arn
}

output "function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.main.function_name
}

output "function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.main.invoke_arn
}

output "function_version" {
  description = "Latest published version of the Lambda function"
  value       = aws_lambda_function.main.version
}

output "function_last_modified" {
  description = "Last modified timestamp of the Lambda function"
  value       = aws_lambda_function.main.last_modified
}

output "role_arn" {
  description = "ARN of the IAM role"
  value       = aws_iam_role.lambda_role.arn
}

output "role_name" {
  description = "Name of the IAM role"
  value       = aws_iam_role.lambda_role.name
}

output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

output "function_url" {
  description = "URL of the Lambda function (if enabled)"
  value       = try(aws_lambda_function_url.url[0].url, null)
}

output "alias_arn" {
  description = "ARN of the Lambda alias"
  value       = aws_lambda_alias.latest.arn
}

output "latest_version" {
  description = "Latest published version number"
  value       = try(aws_lambda_function_version.version[0].version, "$LATEST")
}
