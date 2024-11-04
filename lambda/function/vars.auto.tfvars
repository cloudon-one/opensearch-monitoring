function_name = "monitoring-function"
memory_size = 256
timeout = 300
environment_variables = {
  LOG_LEVEL = "INFO"
}
target_account_roles = [
  "arn:aws:iam::689127934821:role/monitoring-role", #DEV
  "arn:aws:iam::794242591007:role/monitoring-role", #PRE-PROD
  "arn:aws:iam::484646055271:role/monitoring-role"  #PROD
]
schedule_expression = "rate(5 minutes)"