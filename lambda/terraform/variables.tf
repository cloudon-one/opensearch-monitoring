variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "monitored_accounts" {
  description = "List of AWS account IDs to monitor"
  type        = list(string)
}

variable "monitoring_role_name" {
  description = "Name of the IAM role to assume in monitored accounts"
  type        = string
  default     = "LambdaMonitoringRole"
}

variable "opensearch_domain_name" {
  description = "Name for the OpenSearch domain"
  type        = string
  default     = "lambda-monitoring"
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

variable "opensearch_master_user" {
  description = "Master user name for OpenSearch"
  type        = string
  default     = "admin"
}

variable "opensearch_master_user_password" {
  description = "Password for OpenSearch master user"
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "dev"
    Project     = "lambda-monitoring"
  }
}

variable "cross_account_assume_role_enabled" {
  description = "Enable cross-account role assumption"
  type        = bool
  default     = true
}

variable "organization_id_check_enabled" {
  description = "Enable AWS Organization ID verification in trust policies"
  type        = bool
  default     = true
}

variable "vpc_enabled" {
  description = "Whether to deploy OpenSearch in a VPC"
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "VPC ID for OpenSearch deployment"
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "Subnet IDs for OpenSearch deployment"
  type        = list(string)
  default     = []
}

