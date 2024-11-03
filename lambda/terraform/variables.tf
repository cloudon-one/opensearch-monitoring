variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = ""
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "lambda-monitoring"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs"
  type        = list(string)
}

variable "opensearch_instance_type" {
  description = "OpenSearch instance type"
  type        = string
  default     = "t3.small.search"
}

variable "opensearch_instance_count" {
  description = "Number of OpenSearch instances"
  type        = number
  default     = 1
}

variable "opensearch_volume_size" {
  description = "OpenSearch EBS volume size in GB"
  type        = number
  default     = 10
}

variable "opensearch_master_user" {
  description = "OpenSearch master user name"
  type        = string
  sensitive   = true
}

variable "opensearch_master_password" {
  description = "OpenSearch master user password"
  type        = string
  sensitive   = true
}

variable "lambda_layer_zip" {
  description = "Path to Lambda layer ZIP file"
  type        = string
}

variable "lambda_function_zip" {
  description = "Path to Lambda function ZIP file"
  type        = string
}

variable "alert_webhook_url" {
  description = "Webhook URL for alerts"
  type        = string
  sensitive   = true
}

variable "log_level" {
  description = "Log level for Lambda function"
  type        = string
  default     = "INFO"
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
}