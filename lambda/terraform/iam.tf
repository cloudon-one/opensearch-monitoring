# Data source for current AWS account ID
data "aws_caller_identity" "current" {}

# Data source for AWS Organization ID
data "aws_organizations_organization" "current" {}

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
}

# Permissions policy for monitoring
resource "aws_iam_role_policy" "lambda_monitoring_permissions" {
  name   = "lambda-monitoring-permissions"
  role   = aws_iam_role.monitoring_template.id
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
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
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
        Action = "es:*"
        Resource = "${aws_opensearch_domain.monitoring.arn}/*"
      }
    ]
  })
}