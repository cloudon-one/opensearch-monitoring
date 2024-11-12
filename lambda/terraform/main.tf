resource "aws_opensearch_domain" "monitoring" {
  domain_name    = var.opensearch_domain_name
  engine_version = "OpenSearch_2.5"

  cluster_config {
    instance_type          = "t3.small.search"
    instance_count        = 1
    zone_awareness_enabled = false
  }

  ebs_options {
    ebs_enabled = true
    volume_size = 10
  }

  encrypt_at_rest {
    enabled = true
  }

  node_to_node_encryption {
    enabled = true
  }

  advanced_security_options {
    enabled                        = true
    internal_user_database_enabled = true
    master_user_options {
      master_user_name     = "admin"
      master_user_password = random_password.opensearch_master.result
    }
  }
}

# Generate random password for OpenSearch
resource "random_password" "opensearch_master" {
  length  = 16
  special = true
}

# Lambda IAM Role
resource "aws_iam_role" "lambda_monitoring" {
  name = "lambda-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Lambda IAM Policy
resource "aws_iam_role_policy" "lambda_monitoring" {
  name = "lambda-monitoring-policy"
  role = aws_iam_role.lambda_monitoring.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole",
          "cloudwatch:GetMetricData",
          "lambda:ListFunctions",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "es:ESHttp*"
        ]
        Resource = "${aws_opensearch_domain.monitoring.arn}/*"
      }
    ]
  })
}

# Lambda Function
resource "aws_lambda_function" "monitoring" {
  filename         = "function/lambda_function.zip"
  function_name    = "lambda-fleet-monitoring"
  role            = aws_iam_role.lambda_monitoring.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = 300
  memory_size     = 256

  environment {
    variables = {
      MONITORED_ACCOUNTS  = jsonencode(var.monitored_accounts)
      MONITORING_ROLE_NAME = var.monitoring_role_name
      OPENSEARCH_HOST     = aws_opensearch_domain.monitoring.endpoint
      AWS_REGION         = var.aws_region
    }
  }
}

# CloudWatch Event Rule to trigger Lambda
resource "aws_cloudwatch_event_rule" "lambda_monitoring" {
  name                = "lambda-monitoring-trigger"
  description         = "Triggers Lambda monitoring function"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "lambda_monitoring" {
  rule      = aws_cloudwatch_event_rule.lambda_monitoring.name
  target_id = "lambda-fleet-monitoring"
  arn       = aws_lambda_function.monitoring.arn
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.monitoring.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lambda_monitoring.arn
}

resource "aws_lambda_function" "dashboard_setup" {
  filename         = "function/dashboard_setup.zip"
  function_name    = "lambda-dashboard-setup"
  role            = aws_iam_role.lambda_monitoring.arn
  handler         = "dashboard_setup.create_opensearch_dashboards"
  runtime         = "python3.9"
  timeout         = 300
  memory_size     = 256

  environment {
    variables = {
      OPENSEARCH_HOST = aws_opensearch_domain.monitoring.endpoint
      AWS_REGION     = var.aws_region
    }
  }
}

# Additional IAM policy for dashboard setup
resource "aws_iam_role_policy_attachment" "dashboard_setup" {
  role       = aws_iam_role.lambda_monitoring.name
  policy_arn = aws_iam_policy.dashboard_setup.arn
}

resource "aws_iam_policy" "dashboard_setup" {
  name = "lambda-dashboard-setup-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "es:ESHttp*"
        ]
        Resource = "${aws_opensearch_domain.monitoring.arn}/*"
      }
    ]
  })
}

# Null resource to trigger dashboard setup after OpenSearch domain is ready
resource "null_resource" "setup_dashboards" {
  depends_on = [aws_opensearch_domain.monitoring]

  provisioner "local-exec" {
    command = <<EOF
      aws lambda invoke \
        --function-name ${aws_lambda_function.dashboard_setup.function_name} \
        --region ${var.aws_region} \
        response.json
    EOF
  }
}

# CloudWatch Log Group for cross-account access monitoring
resource "aws_cloudwatch_log_group" "cross_account_access" {
  name              = "/aws/lambda/${var.monitoring_role_name}/cross-account-access"
  retention_in_days = 14

  tags = {
    Environment = "production"
    Service     = "lambda-monitoring"
  }
}

# SNS Topic for cross-account access notifications
resource "aws_sns_topic" "cross_account_access" {
  name = "lambda-monitoring-cross-account-access"
}

# CloudWatch Metric Filter for failed cross-account access
resource "aws_cloudwatch_log_metric_filter" "failed_cross_account_access" {
  name           = "failed-cross-account-access"
  pattern        = "?Error ?error ?exception ?Exception"
  log_group_name = aws_cloudwatch_log_group.cross_account_access.name

  metric_transformation {
    name      = "FailedCrossAccountAccess"
    namespace = "LambdaMonitoring"
    value     = "1"
  }
}

# CloudWatch Alarm for failed cross-account access
resource "aws_cloudwatch_metric_alarm" "failed_cross_account_access" {
  alarm_name          = "failed-cross-account-access"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FailedCrossAccountAccess"
  namespace           = "LambdaMonitoring"
  period             = "300"
  statistic          = "Sum"
  threshold          = "0"
  alarm_description  = "This metric monitors failed cross-account access attempts"
  alarm_actions      = [aws_sns_topic.cross_account_access.arn]
}