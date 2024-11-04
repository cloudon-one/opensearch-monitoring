terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Optional but recommended: specify allowed AWS account IDs to prevent accidents
  allowed_account_ids = [var.aws_account_id]

  # Optional: assume role configuration if needed
  dynamic "assume_role" {
    for_each = var.assume_role_arn != null ? [1] : []
    content {
      role_arn = var.assume_role_arn
    }
  }

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "Lambda-Monitoring"
      ManagedBy   = "Terraform"
    }
  }
}
# Lambda function configuration
resource "aws_lambda_function" "monitoring" {
  filename         = "lambda_function.zip"
  function_name    = var.function_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = 300
  memory_size     = 256
  
  # Add VPC configuration if specified
  dynamic "vpc_config" {
    for_each = var.vpc_subnet_ids != null && var.vpc_security_group_ids != null ? [1] : []
    content {
      subnet_ids         = var.vpc_subnet_ids
      security_group_ids = var.vpc_security_group_ids
    }
  }

  environment {
    variables = {
      ACCOUNTS_CONFIG    = jsonencode(var.monitoring_accounts)
      ALERT_CONFIG      = jsonencode(var.alert_config)
      ALERT_THRESHOLDS  = jsonencode(var.alert_thresholds)
      METRICS_BUCKET    = aws_s3_bucket.metrics.id
      SLACK_WEBHOOK_URL = var.slack_webhook_url
      PAGERDUTY_API_KEY = var.pagerduty_api_key
    }
  }

  tags = var.tags
}

# Lambda function URL (if enabled)
resource "aws_lambda_function_url" "function_url" {
  count              = var.create_function_url ? 1 : 0
  function_name      = aws_lambda_function.monitoring.function_name
  authorization_type = "AWS_IAM"

  cors {
    allow_credentials = true
    allow_origins     = ["*"]
    allow_methods     = ["*"]
    allow_headers     = ["date", "keep-alive"]
    expose_headers    = ["keep-alive", "date"]
    max_age          = 86400
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.monitoring.function_name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# S3 bucket for metrics storage
resource "aws_s3_bucket" "metrics" {
  bucket = var.metrics_bucket_name
  tags   = var.tags
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "metrics" {
  bucket = aws_s3_bucket.metrics.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 lifecycle rules
resource "aws_s3_bucket_lifecycle_configuration" "metrics" {
  bucket = aws_s3_bucket.metrics.id

  rule {
    id     = "hot_to_warm"
    status = "Enabled"

    filter {
      prefix = "hot/"
    }

    transition {
      days          = 7
      storage_class = "STANDARD_IA"
    }
  }

  rule {
    id     = "warm_to_cold"
    status = "Enabled"

    filter {
      prefix = "warm/"
    }

    transition {
      days          = 30
      storage_class = "GLACIER"
    }
  }

  rule {
    id     = "cold_cleanup"
    status = "Enabled"

    filter {
      prefix = "cold/"
    }

    expiration {
      days = 365
    }
  }
}

# Lambda CloudWatch Event rule
resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "${var.function_name}-schedule"
  description         = "Schedule for Lambda monitoring function"
  schedule_expression = var.schedule_expression
  tags               = var.tags
}

# CloudWatch Event target
resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.schedule.name
  target_id = "Lambda"
  arn       = aws_lambda_function.monitoring.arn
}

# Lambda permission for CloudWatch Events
resource "aws_lambda_permission" "cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.monitoring.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${var.function_name}-role"

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

  tags = var.tags
}

# Lambda basic execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# VPC access policy (if VPC config is provided)
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  count      = var.vpc_subnet_ids != null ? 1 : 0
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Custom policy for Lambda function
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.function_name}-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = var.monitoring_accounts[*].role_arn
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
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
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:StartQuery",
          "logs:GetQueryResults"
        ]
        Resource = [
          "arn:aws:logs:*:*:log-group:/aws/lambda/*",
          "arn:aws:logs:*:*:log-group:/aws/lambda/*:log-stream:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.metrics.arn,
          "${aws_s3_bucket.metrics.arn}/*"
        ]
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
          "ce:GetCostAndUsage"
        ]
        Resource = "*"
      }
    ]
  })
}

# Optional KMS key for encryption
resource "aws_kms_key" "lambda" {
  count                   = var.create_kms_key ? 1 : 0
  description             = "KMS key for Lambda function ${var.function_name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags                    = var.tags
}

resource "aws_kms_alias" "lambda" {
  count         = var.create_kms_key ? 1 : 0
  name          = "alias/${var.function_name}"
  target_key_id = aws_kms_key.lambda[0].key_id
}