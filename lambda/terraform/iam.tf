# Data source for current AWS account ID
data "aws_caller_identity" "current" {}

# Data source for AWS Organization ID
data "aws_organizations_organization" "current" {}

# OpenSearch setup role
resource "aws_iam_role" "opensearch_setup" {
  name = "opensearch-setup-role"
  path = "/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# OpenSearch setup role policy
resource "aws_iam_role_policy" "opensearch_setup" {
  name = "opensearch-setup-policy"
  role = aws_iam_role.opensearch_setup.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "es:ESHttpGet",
          "es:ESHttpPost",
          "es:ESHttpPut",
          "es:ESHttpDelete"
        ]
        Resource = "${aws_opensearch_domain.monitoring.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# IAM role for Lambda monitoring in monitored accounts (template)
resource "aws_iam_role" "monitoring_template" {
  name = var.monitoring_role_name
  path = "/"

  # Trust policy for cross-account access
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = [
            "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${aws_iam_role.lambda_monitoring.name}",
            "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${aws_iam_role.opensearch_setup.name}"
          ]
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:PrincipalOrgID" = data.aws_organizations_organization.current.id
          }
        }
      }
    ]
  })

  # Permissions policy for monitoring
  inline_policy {
    name = "lambda-monitoring-permissions"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "cloudwatch:GetMetricData",
            "cloudwatch:GetMetricStatistics",
            "cloudwatch:ListMetrics"
          ]
          Resource = "*"
        },
        {
          Effect = "Allow"
          Action = [
            "lambda:ListFunctions",
            "lambda:GetFunction",
            "lambda:GetFunctionConfiguration"
          ]
          Resource = "*"
        },
        {
          Effect = "Allow"
          Action = [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ]
          Resource = "arn:aws:logs:*:*:*"
        }
      ]
    })
  }
}

# Enhanced Lambda monitoring role
resource "aws_iam_role" "lambda_monitoring" {
  name = "lambda-fleet-monitoring-role"
  path = "/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Enhanced policy for Lambda monitoring role
resource "aws_iam_role_policy" "lambda_monitoring_enhanced" {
  name = "lambda-monitoring-enhanced-policy"
  role = aws_iam_role.lambda_monitoring.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = [
          for account_id in var.monitored_accounts :
          "arn:aws:iam::${account_id}:role/${var.monitoring_role_name}"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
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
          "es:ESHttpGet",
          "es:ESHttpPost",
          "es:ESHttpPut",
          "es:ESHttpDelete"
        ]
        Resource = "${aws_opensearch_domain.monitoring.arn}/*"
      }
    ]
  })
}

# OpenSearch domain policy
resource "aws_opensearch_domain_policy" "monitoring" {
  domain_name = aws_opensearch_domain.monitoring.domain_name

  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = [
            aws_iam_role.lambda_monitoring.arn,
            aws_iam_role.opensearch_setup.arn
          ]
        }
        Action   = "es:*"
        Resource = "${aws_opensearch_domain.monitoring.arn}/*"
      }
    ]
  })
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
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors failed cross-account access attempts"
  alarm_actions       = [aws_sns_topic.cross_account_access.arn]
}

