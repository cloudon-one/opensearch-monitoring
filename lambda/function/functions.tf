# functions.tf
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

  # Enable function URL if specified
  dynamic "function_url_config" {
    for_each = var.create_function_url ? [1] : []
    content {
      authorization_type = "AWS_IAM"
      cors {
        allow_origins = ["*"]
      }
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