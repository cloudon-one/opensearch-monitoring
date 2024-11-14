# Random password for OpenSearch master user
resource "random_password" "opensearch_master" {
  length  = 16
  special = true
}

# AWS Secrets Manager secret for OpenSearch master user password
resource "aws_secretsmanager_secret" "opensearch_master" {
  name = "opensearch-master-user-password"
}

resource "aws_secretsmanager_secret_version" "opensearch_master" {
  secret_id     = aws_secretsmanager_secret.opensearch_master.id
  secret_string = random_password.opensearch_master.result
}

# OpenSearch Domain
resource "aws_opensearch_domain" "monitoring" {
  domain_name    = var.opensearch_domain_name
  engine_version = "OpenSearch_2.5"

  cluster_config {
    instance_type          = var.opensearch_instance_type
    instance_count         = var.opensearch_instance_count
    zone_awareness_enabled = var.opensearch_instance_count > 1

    # Add zone awareness config if multiple instances
    dynamic "zone_awareness_config" {
      for_each = var.opensearch_instance_count > 1 ? [1] : []
      content {
        availability_zone_count = 2
      }
    }
  }

  vpc_options {
    subnet_ids         = var.vpc_enabled ? var.subnet_ids : null
    security_group_ids = var.vpc_enabled ? [aws_security_group.opensearch[0].id] : null
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
    enforce_https           = true
    tls_security_policy     = "Policy-Min-TLS-1-2-2019-07"
    custom_endpoint_enabled = false
  }

  advanced_security_options {
    enabled                        = true
    internal_user_database_enabled = true
    master_user_options {
      master_user_name     = var.opensearch_master_user
      master_user_password = random_password.opensearch_master.result
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "lambda-monitoring-opensearch"
    }
  )

  depends_on = [aws_secretsmanager_secret_version.opensearch_master]
}

# Security group for OpenSearch if VPC enabled
resource "aws_security_group" "opensearch" {
  count       = var.vpc_enabled ? 1 : 0
  name        = "opensearch-monitoring"
  description = "Security group for OpenSearch monitoring domain"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda_monitoring.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "opensearch-monitoring"
    }
  )
}

# Security group for Lambda function
resource "aws_security_group" "lambda_monitoring" {
  name        = "lambda-monitoring"
  description = "Security group for Lambda monitoring function"
  vpc_id      = var.vpc_enabled ? var.vpc_id : null

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "lambda-monitoring"
    }
  )
}


# Lambda Function
resource "aws_lambda_function" "monitoring" {
  filename      = "function/lambda_function.zip"
  function_name = "lambda-fleet-monitoring"
  role          = aws_iam_role.lambda_monitoring.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"
  timeout       = 300
  memory_size   = 512

  environment {
    variables = {
      MONITORED_ACCOUNTS   = jsonencode(var.monitored_accounts)
      MONITORING_ROLE_NAME = var.monitoring_role_name
      OPENSEARCH_HOST      = aws_opensearch_domain.monitoring.endpoint
      AWS_REGION           = var.aws_region
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
  filename      = "function/dashboard_setup.zip"
  function_name = "lambda-dashboard-setup"
  role          = aws_iam_role.lambda_monitoring.arn
  handler       = "dashboard_setup.create_opensearch_dashboards"
  runtime       = "python3.11"
  timeout       = 300
  memory_size   = 256

  environment {
    variables = {
      OPENSEARCH_HOST = aws_opensearch_domain.monitoring.endpoint
      AWS_REGION      = var.aws_region
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
