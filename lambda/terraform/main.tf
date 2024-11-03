terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  backend "s3" {
    # Configure your state backend
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "lambda-monitoring"
      Terraform   = "true"
    }
  }
}

# Random string for unique naming
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# OpenSearch Domain
resource "aws_opensearch_domain" "monitoring" {
  domain_name    = "${var.project_name}-${var.environment}-${random_string.suffix.result}"
  engine_version = "OpenSearch_2.5"

  cluster_config {
    instance_type            = var.opensearch_instance_type
    instance_count          = var.opensearch_instance_count
    zone_awareness_enabled  = var.opensearch_instance_count > 1
    dedicated_master_enabled = false
  }

  ebs_options {
    ebs_enabled = true
    volume_size = var.opensearch_volume_size
    volume_type = "gp3"
  }

  encrypt_at_rest {
    enabled = true
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

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

  depends_on = [aws_iam_service_linked_role.opensearch]
}

# Lambda Layer
resource "aws_lambda_layer_version" "monitoring_deps" {
  filename         = var.lambda_layer_zip
  layer_name       = "${var.project_name}-dependencies-${var.environment}"
  description      = "Dependencies for Lambda monitoring function"
  compatible_runtimes = ["python3.9"]

  compatible_architectures = ["x86_64", "arm64"]
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
    }
  }

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }
}

# Security Groups
resource "aws_security_group" "lambda" {
  name        = "${var.project_name}-lambda-${var.environment}"
  description = "Security group for Lambda monitoring function"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "opensearch" {
  name        = "${var.project_name}-opensearch-${var.environment}"
  description = "Security group for OpenSearch domain"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role-${var.environment}"

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

resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "lambda_monitoring" {
  name = "${var.project_name}-lambda-policy-${var.environment}"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "es:ESHttp*"
        ]
        Resource = "${aws_opensearch_domain.monitoring.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:ListFunctions",
          "lambda:GetFunction"
        ]
        Resource = "*"
      }
    ]
  })
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "monitoring" {
  name              = "/aws/lambda/${aws_lambda_function.monitoring.function_name}"
  retention_in_days = var.log_retention_days
}

# Service Linked Role for OpenSearch
resource "aws_iam_service_linked_role" "opensearch" {
  aws_service_name = "opensearchservice.amazonaws.com"
}

# Subscription Function for Setting Up Log Subscriptions
resource "aws_lambda_function" "subscription_setup" {
  filename      = data.archive_file.subscription_setup.output_path
  function_name = "${var.project_name}-subscription-setup-${var.environment}"
  role         = aws_iam_role.subscription_setup_role.arn
  handler      = "index.handler"
  runtime      = "python3.9"
  timeout      = 300

  environment {
    variables = {
      MONITORING_FUNCTION_ARN = aws_lambda_function.monitoring.arn
    }
  }
}

# Archive file for subscription setup function
data "archive_file" "subscription_setup" {
  type        = "zip"
  output_path = "${path.module}/subscription_setup.zip"

  source {
    content  = <<EOF
import boto3
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    try:
        logs = boto3.client('logs')
        lambda_client = boto3.client('lambda')
        
        # Get all Lambda functions
        functions = lambda_client.list_functions()['Functions']
        
        for function in functions:
            log_group_name = f"/aws/lambda/{function['FunctionName']}"
            try:
                # Create subscription filter
                logs.put_subscription_filter(
                    logGroupName=log_group_name,
                    filterName='lambda-monitoring',
                    filterPattern='',
                    destinationArn=os.environ['MONITORING_FUNCTION_ARN']
                )
                logger.info(f"Created subscription for {log_group_name}")
            except Exception as e:
                logger.error(f"Error creating subscription for {log_group_name}: {str(e)}")
                
        return {'statusCode': 200}
    except Exception as e:
        logger.error(f"Error: {str(e)}")
        return {'statusCode': 500}
EOF
    filename = "index.py"
  }
}

# IAM Role for Subscription Setup Function
resource "aws_iam_role" "subscription_setup_role" {
  name = "${var.project_name}-subscription-setup-role-${var.environment}"

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

resource "aws_iam_role_policy" "subscription_setup" {
  name = "${var.project_name}-subscription-setup-policy-${var.environment}"
  role = aws_iam_role.subscription_setup_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:PutSubscriptionFilter",
          "logs:DeleteSubscriptionFilter",
          "lambda:ListFunctions"
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
        Resource = [
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project_name}-subscription-setup-${var.environment}:*"
        ]
      }
    ]
  })
}

# Current AWS Account ID
data "aws_caller_identity" "current" {}
