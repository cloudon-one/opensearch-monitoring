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