# OpenSearch Domain
resource "aws_opensearch_domain" "monitoring" {
  domain_name    = "${var.function_name}-dev"
  engine_version = "OpenSearch_2.15"

  cluster_config {
    instance_type          = var.opensearch_instance_type
    instance_count         = var.opensearch_instance_count
    zone_awareness_enabled = var.opensearch_instance_count > 1
  }

  ebs_options {
    ebs_enabled = true
    volume_size = var.opensearch_volume_size
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
    subnet_ids         = [var.vpc_subnet_ids[0]] # Using first subnet for single-AZ deployment
    security_group_ids = [aws_security_group.opensearch.id]
  }

  # Access policy without self-reference
  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action   = "es:*"
        Resource = "*"
        Condition = {
          IpAddress = {
            "aws:SourceIp" = ["0.0.0.0/0"]
          }
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# OpenSearch access policy (applied after domain creation)
resource "aws_opensearch_domain_policy" "main" {
  domain_name = aws_opensearch_domain.monitoring.domain_name

  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action   = "es:*"
        Resource = "${aws_opensearch_domain.monitoring.arn}/*"
      }
    ]
  })
}

# Security group for Lambda function
resource "aws_security_group" "lambda_sg" {
  name_prefix = "${var.function_name}-lambda-"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "${var.function_name}-lambda"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Security group for OpenSearch
resource "aws_security_group" "opensearch" {
  name_prefix = "${var.function_name}-opensearch-"
  vpc_id      = var.vpc_id

  # Allow HTTPS access from anywhere
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS access from anywhere"
  }

  # Allow access from Lambda security group
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda_sg.id]
    description     = "Allow access from Lambda function"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "${var.function_name}-opensearch"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# VPC Endpoints for OpenSearch internet access
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  tags = {
    Name        = "${var.function_name}-s3-endpoint"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Create a NAT Gateway for internet access
resource "aws_eip" "nat" {
  domain = "vpc"
  tags = {
    Name        = "${var.function_name}-nat-eip"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = var.vpc_subnet_ids[0] # Use the first subnet as the public subnet

  tags = {
    Name        = "${var.function_name}-nat-gateway"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Update route tables
resource "aws_route_table" "private" {
  vpc_id = var.vpc_id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name        = "${var.function_name}-private-rt"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(var.vpc_subnet_ids)
  subnet_id      = var.vpc_subnet_ids[count.index]
  route_table_id = aws_route_table.private.id
}

# Lambda Function
resource "aws_lambda_function" "monitoring" {
  filename      = "${path.module}/../function/lambda_function.zip"
  function_name = var.function_name
  role          = aws_iam_role.lambda_role.arn
  handler       = "monitoring_function.lambda_handler"
  runtime       = "python3.9"
  timeout       = 300
  memory_size   = 256

  depends_on = [null_resource.lambda_package]

  vpc_config {
    subnet_ids         = var.vpc_subnet_ids
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      ACCOUNTS_CONFIG     = jsonencode(var.monitoring_accounts)
      ALERT_CONFIG        = jsonencode(var.alert_config)
      ALERT_THRESHOLDS    = jsonencode(var.alert_thresholds)
      METRICS_BUCKET      = aws_s3_bucket.metrics.id
      OPENSEARCH_ENDPOINT = aws_opensearch_domain.monitoring.endpoint
      SLACK_WEBHOOK_URL   = var.slack_webhook_url
      PAGERDUTY_API_KEY   = var.pagerduty_api_key
      LOG_LEVEL           = lookup(var.environment_variables, "LOG_LEVEL", "INFO")
    }
  }
}

# S3 bucket for metrics storage
resource "aws_s3_bucket" "metrics" {
  bucket = var.metrics_bucket_name
}

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
      days          = 30
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
      days          = 90
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

# Package the Lambda function
resource "null_resource" "lambda_package" {
  triggers = {
    lambda_file  = filemd5("${path.module}/../function/monitoring_function.py")
    requirements = filemd5("${path.module}/../function/requirements.txt")
  }

  provisioner "local-exec" {
    command = <<EOT
      cd ${path.module}/../function
      pip install -r requirements.txt -t package/
      cd package
      zip -r9 ../lambda_function.zip .
      cd ..
      zip -g lambda_function.zip monitoring_function.py
    EOT
  }
}
