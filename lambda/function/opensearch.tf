# opensearch.tf

locals {
  # Get the first subnet ID for single-AZ deployment
  opensearch_subnet_id = var.vpc_subnet_ids[0]
}

# OpenSearch Domain
resource "aws_opensearch_domain" "monitoring" {
  domain_name    = "${var.function_name}-logs"
  engine_version = "OpenSearch_2.5"

  cluster_config {
    instance_type          = var.opensearch_instance_type
    instance_count         = var.opensearch_instance_count
    zone_awareness_enabled = false  # Disabled for single-AZ deployment
  }

  ebs_options {
    ebs_enabled = true
    volume_size = var.opensearch_volume_size
    volume_type = "gp3"
  }

  vpc_options {
    subnet_ids         = [local.opensearch_subnet_id]  # Use single subnet
    security_group_ids = [aws_security_group.opensearch.id]
  }

  encrypt_at_rest {
    enabled = true
    kms_key_id = var.create_kms_key ? aws_kms_key.lambda[0].arn : null
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

  tags = var.tags
}

# Security Group for OpenSearch
resource "aws_security_group" "opensearch" {
  name        = "${var.function_name}-opensearch-sg"
  description = "Security group for OpenSearch domain"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  tags = var.tags
}

# Security Group for Lambda
resource "aws_security_group" "lambda" {
  name        = "${var.function_name}-lambda-sg"
  description = "Security group for Lambda function"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

# Optional: Add outputs for OpenSearch domain
output "opensearch_endpoint" {
  description = "OpenSearch domain endpoint"
  value       = aws_opensearch_domain.monitoring.endpoint
}

output "opensearch_dashboard_endpoint" {
  description = "OpenSearch dashboard endpoint"
  value       = aws_opensearch_domain.monitoring.dashboard_endpoint
}