output "lambda_function_arn" {
  description = "ARN of the Lambda monitoring function"
  value       = aws_lambda_function.monitoring.arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda IAM role"
  value       = aws_iam_role.lambda
}