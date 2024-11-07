# AWS Configuration Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

# Lambda Function Variables
variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
}

variable "memory_size" {
  description = "Memory size for Lambda function"
  type        = number
  default     = 256
}

variable "timeout" {
  description = "Lambda function timeout"
  type        = number
  default     = 300
}

variable "environment_variables" {
  description = "Environment variables for Lambda function"
  type        = map(string)
  default     = {}
}

# Monitoring Configuration
variable "target_account_roles" {
  description = "List of IAM roles ARNs in target accounts for monitoring"
  type        = list(string)
  default     = []
}

variable "monitoring_accounts" {
  description = "List of accounts to monitor"
  type = list(object({
    account_id = string
    region     = string
    role_arn   = string
  }))
  default = []
}

# Schedule Configuration
variable "schedule_expression" {
  description = "CloudWatch Events schedule expression"
  type        = string
  default     = "rate(5 minutes)"
}

# Feature Flags
variable "create_function_url" {
  description = "Whether to create Lambda function URL"
  type        = bool
  default     = false
}

# VPC Configuration
variable "vpc_id" {
  description = "VPC ID for Lambda deployment"
  type        = string
}

variable "vpc_subnet_ids" {
  description = "List of VPC subnet IDs"
  type        = list(string)
}

# Integration Variables
variable "slack_webhook_url" {
  description = "Slack webhook URL"
  type        = string
  sensitive   = true
}

variable "pagerduty_api_key" {
  description = "PagerDuty API key"
  type        = string
  sensitive   = true
}

# Storage Configuration
variable "metrics_bucket_name" {
  description = "Name of S3 bucket for metrics storage"
  type        = string
}

# OpenSearch Configuration
variable "opensearch_master_user" {
  description = "OpenSearch master user"
  type        = string
}

variable "opensearch_master_password" {
  description = "OpenSearch master password"
  type        = string
  sensitive   = true
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
  description = "Size of OpenSearch EBS volume in GB"
  type        = number
  default     = 10
}

# Additional Variables
variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}

# Alert Configuration Variables
variable "alert_config" {
  description = "Alert configuration for different channels"
  type = object({
    slack = object({
      channel    = string
      username   = optional(string)
      icon_emoji = optional(string)
    })
    pagerduty = object({
      service_key = string
      severity    = optional(string)
    })
  })
}

variable "alert_thresholds" {
  description = "Thresholds for different types of alerts"
  type = object({
    error_rate = object({
      warning  = number
      critical = number
    })
    memory_usage = object({
      warning  = number
      critical = number
    })
    duration = object({
      warning  = number
      critical = number
    })
    cost = object({
      warning  = number
      critical = number
    })
  })
}
