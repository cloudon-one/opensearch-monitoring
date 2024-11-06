function_name = "monitoring-function"
memory_size   = 256
timeout       = 300
environment_variables = {
  LOG_LEVEL = "INFO"
}
target_account_roles = [
  "arn:aws:iam::689127934821:role/monitoring-role", #DEV
  "arn:aws:iam::794242591007:role/monitoring-role", #PRE-PROD
  "arn:aws:iam::484646055271:role/monitoring-role"  #PROD
]
schedule_expression = "rate(5 minutes)"
create_function_url = true

vpc_id = "vpc-059c6b66f47d85f0e"
vpc_subnet_ids = [
  "subnet-018cc508b104e628a",
  "subnet-00927783aa2d22192",
  "subnet-0e5408ab70119fe12",
  "subnet-021a29b81ad05febf"
]

slack_webhook_url = "https://hooks.slack.com/services/T01B7SGGMLB/B01B7SGGMLB/1B7SGGMLB"
pagerduty_api_key = "PAGERDUTY_API_KEY"
metrics_bucket_name = "kipp-dev-function-metrics-bucket"

monitoring_accounts = [
  {
    account_id = "689127934821",
    region     = "eu-west-1",
    role_arn   = "arn:aws:iam::689127934821:role/monitoring-role"
  }
]

aws_region      = "eu-west-1"
aws_account_id  = "689127934821"  # dev
environment     = "dev"

opensearch_master_user = "dev_admin"
opensearch_master_password = "Secured@Admin!123"
opensearch_instance_type = "t3.small.search"
opensearch_instance_count = 1
opensearch_volume_size = 10