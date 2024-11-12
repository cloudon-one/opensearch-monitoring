variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
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

variable "opensearch_master_user_password" {
  description = "Password for OpenSearch master user"
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {
    Environment = "dev"
    Project     = "lambda-monitoring"
  }
}