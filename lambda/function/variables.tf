variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
}

variable "timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
}

variable "memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 128
}

variable "environment_variables" {
  description = "Environment variables for the Lambda function"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "subnet_ids" {
  description = "List of subnet IDs for VPC configuration"
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "List of security group IDs for VPC configuration"
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
}

variable "additional_policy_statements" {
  description = "Additional IAM policy statements for Lambda role"
  type        = list(any)
  default     = []
}

variable "create_function_url" {
  description = "Whether to create a function URL"
  type        = bool
  default     = false
}

variable "function_url_auth_type" {
  description = "Authentication type for function URL (NONE or AWS_IAM)"
  type        = string
  default     = "AWS_IAM"
}

variable "cors_allow_credentials" {
  description = "Whether to allow credentials for CORS"
  type        = bool
  default     = false
}

variable "cors_allow_origins" {
  description = "Allowed origins for CORS"
  type        = list(string)
  default     = ["*"]
}

variable "cors_allow_methods" {
  description = "Allowed methods for CORS"
  type        = list(string)
  default     = ["*"]
}

variable "cors_allow_headers" {
  description = "Allowed headers for CORS"
  type        = list(string)
  default     = ["*"]
}

variable "cors_expose_headers" {
  description = "Headers to expose for CORS"
  type        = list(string)
  default     = []
}

variable "cors_max_age" {
  description = "Max age for CORS preflight cache"
  type        = number
  default     = 0
}

variable "schedule_expression" {
  description = "CloudWatch Events schedule expression"
  type        = string
  default     = null
}

variable "publish_version" {
  description = "Whether to publish a new Lambda version"
  type        = bool
  default     = false
}

variable "target_account_roles" {
  description = "List of IAM role ARNs in target accounts that the Lambda function can assume"
  type        = list(string)
  default     = []
}
