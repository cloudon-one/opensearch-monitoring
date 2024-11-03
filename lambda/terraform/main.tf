# Load and validate metrics configuration from file
locals {
  metrics_config = jsondecode(file("${path.module}/lambda_monitor.json"))
}

# OpenSearch Domain
resource "aws_opensearch_domain" "monitoring" {
  domain_name    = "${var.project_name}-${var.environment}-${random_string.suffix.result}"
  engine_version = "OpenSearch_2.5"

  cluster_config {
    instance_type            = var.opensearch_instance_type
    instance_count          = var.opensearch_instance_count
    zone_awareness_enabled  = var.opensearch_instance_count > 1
  }

  ebs_options {
    ebs_enabled = true
    volume_size = var.opensearch_volume_size
    volume_type = "gp3"
  }

  # Apply index template from configuration
  advanced_options = {
    "indices.query.bool.max_clause_count" = "8192",
    "override_main_response_version" = "true"
  }

  # Apply lifecycle policy from configuration
  advanced_security_options {
    enabled                        = true
    internal_user_database_enabled = true
    master_user_options {
      master_user_name     = var.opensearch_master_user
      master_user_password = var.opensearch_master_password
    }
  }

  vpc_options {
    subnet_ids         = var.subnet_ids
    security_group_ids = [aws_security_group.opensearch.id]
  }
}

# Lambda Function
resource "aws_lambda_function" "monitoring" {
  filename         = var.lambda_function_zip
  function_name    = "${var.project_name}-monitor-${var.environment}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_monitor.lambda_handler"
  runtime         = "python3.9"
  timeout         = 300
  memory_size     = 256

  layers = [aws_lambda_layer_version.monitoring_deps.arn]

  environment {
    variables = {
      OPENSEARCH_ENDPOINT = aws_opensearch_domain.monitoring.endpoint
      ALERT_WEBHOOK_URL  = var.alert_webhook_url
      ENVIRONMENT       = var.environment
      LOG_LEVEL        = var.log_level
      METRICS_CONFIG   = jsonencode(local.metrics_config)
      SLACK_WEBHOOK_URL = var.slack_webhook_url
      PAGERDUTY_API_KEY = var.pagerduty_api_key
    }
  }

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }
}

# S3 Bucket for configurations
resource "aws_s3_bucket" "lambda_artifacts" {
  bucket = "${var.project_name}-artifacts-${var.environment}-${random_string.suffix.result}"
}

# Enable versioning
resource "aws_s3_bucket_versioning" "lambda_artifacts" {
  bucket = aws_s3_bucket.lambda_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Upload configuration
resource "aws_s3_object" "metrics_config" {
  bucket = aws_s3_bucket.lambda_artifacts.id
  key    = "config/lambda_monitor.json"
  content = jsonencode(local.metrics_config)
  content_type = "application/json"
}

# SSM Parameters for sensitive values
resource "aws_ssm_parameter" "slack_webhook" {
  name  = "/${var.project_name}/${var.environment}/slack_webhook_url"
  type  = "SecureString"
  value = var.slack_webhook_url
}

resource "aws_ssm_parameter" "pagerduty_key" {
  name  = "/${var.project_name}/${var.environment}/pagerduty_api_key"
  type  = "SecureString"
  value = var.pagerduty_api_key
}

# Add necessary variables
variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications"
  type        = string
  sensitive   = true
}

variable "pagerduty_api_key" {
  description = "PagerDuty API key for alerts"
  type        = string
  sensitive   = true
}

# Lambda permissions for SSM
resource "aws_iam_role_policy" "lambda_ssm" {
  name = "${var.project_name}-lambda-ssm-${var.environment}"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          aws_ssm_parameter.slack_webhook.arn,
          aws_ssm_parameter.pagerduty_key.arn
        ]
      }
    ]
  })
}

# Add OpenSearch template creation Lambda
resource "aws_lambda_function" "opensearch_setup" {
  filename         = var.setup_function_zip
  function_name    = "${var.project_name}-setup-${var.environment}"
  role            = aws_iam_role.setup_role.arn
  handler         = "setup.handler"
  runtime         = "python3.9"
  timeout         = 300

  environment {
    variables = {
      OPENSEARCH_ENDPOINT = aws_opensearch_domain.monitoring.endpoint
      METRICS_CONFIG     = jsonencode(local.metrics_config)
    }
  }
}

# Setup function role
resource "aws_iam_role" "setup_role" {
  name = "${var.project_name}-setup-role-${var.environment}"

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

# Invoke setup function after OpenSearch domain creation
resource "null_resource" "setup_opensearch" {
  triggers = {
    opensearch_endpoint = aws_opensearch_domain.monitoring.endpoint
    config_hash        = sha256(jsonencode(local.metrics_config))
  }

  provisioner "local-exec" {
    command = "aws lambda invoke --function-name ${aws_lambda_function.opensearch_setup.function_name} --payload '{}' response.json"
  }

  depends_on = [
    aws_lambda_function.opensearch_setup,
    aws_opensearch_domain.monitoring
  ]
}