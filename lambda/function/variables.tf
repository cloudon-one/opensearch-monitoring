# variables.tf
variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
  default     = "lambda-monitoring"
}

variable "monitoring_accounts" {
  description = "List of accounts to monitor"
  type = list(object({
    account_id = string
    region     = string
    role_arn   = string
  }))
}

variable "schedule_expression" {
  description = "CloudWatch Events schedule expression"
  type        = string
  default     = "rate(5 minutes)"
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
}

variable "metrics_bucket_name" {
  description = "Name of the S3 bucket for storing metrics"
  type        = string
}

variable "alert_config" {
  description = "Alert configuration for different channels"
  type        = map(any)
  default     = {}
}

variable "alert_thresholds" {
  description = "Thresholds for different alert conditions"
  type        = map(any)
  default     = {}
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications"
  type        = string
  default     = ""
}

variable "pagerduty_api_key" {
  description = "PagerDuty API key for notifications"
  type        = string
  default     = ""
}

variable "vpc_subnet_ids" {
  description = "List of VPC subnet IDs for Lambda function"
  type        = list(string)
  default     = null
}

variable "vpc_security_group_ids" {
  description = "List of VPC security group IDs for Lambda function"
  type        = list(string)
  default     = null
}

variable "create_function_url" {
  description = "Whether to create a function URL"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

# Add to variables.tf

variable "create_kms_key" {
  description = "Whether to create a KMS key for encryption"
  type        = bool
  default     = false
}

variable "kms_key_deletion_window" {
  description = "Duration in days after which the KMS key is deleted after destruction"
  type        = number
  default     = 7
}

# Add to variables.tf

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "eu-west-1"
}

variable "aws_account_id" {
  description = "AWS account ID where resources will be created"
  type        = string
}

variable "assume_role_arn" {
  description = "ARN of the IAM role to assume (optional)"
  type        = string
  default     = null
}

variable "environment" {
  description = "Environment name (e.g., dev, prod, staging)"
  type        = string
  default     = ""
}