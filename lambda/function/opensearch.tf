
locals {
  # Get the first subnet ID for single-AZ deployment
  opensearch_subnet_id = var.vpc_subnet_ids[0]
  dashboard_file = "${path.module}/dashboards/lambda_monitoring.json"
  
  # Base64 encode credentials for basic auth
  auth_header = base64encode("${var.opensearch_master_user}:${var.opensearch_master_password}")
}

# OpenSearch Domain
resource "aws_opensearch_domain" "monitoring" {
  domain_name    = "${var.function_name}-logs"
  engine_version = "OpenSearch_2.15"

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


# Wait for OpenSearch domain to be ready
resource "time_sleep" "wait_for_opensearch" {
  depends_on = [aws_opensearch_domain.monitoring]
  
  create_duration = "60s"
}

# Import dashboard configuration
resource "null_resource" "import_dashboard" {
  depends_on = [time_sleep.wait_for_opensearch]

  triggers = {
    dashboard_content = filemd5(local.dashboard_file)
  }

  provisioner "local-exec" {
    command = <<EOT
      # Create index pattern
      curl -X PUT \
        "https://${aws_opensearch_domain.monitoring.endpoint}/_dashboards/api/saved_objects/index-pattern/metrics-*" \
        -H "Authorization: Basic ${local.auth_header}" \
        -H "Content-Type: application/json" \
        -H "osd-xsrf: true" \
        -d '{"attributes":{"title":"metrics-*","timeFieldName":"timestamp"}}'

      # Import dashboard
      curl -X POST \
        "https://${aws_opensearch_domain.monitoring.endpoint}/_dashboards/api/saved_objects/_import?overwrite=true" \
        -H "Authorization: Basic ${local.auth_header}" \
        -H "osd-xsrf: true" \
        -H "Content-Type: multipart/form-data" \
        -F "file=@${local.dashboard_file}"
    EOT
  }
}

resource "null_resource" "import_dashboards" {
  depends_on = [time_sleep.wait_for_opensearch]

  triggers = {
    dashboard_content = filemd5(local.dashboard_file)
    script_content = filemd5("${path.module}/scripts/manage_dashboard.py")
  }

  provisioner "local-exec" {
    command = <<EOT
      python3 ${path.module}/scripts/manage_dashboard.py \
        --endpoint ${aws_opensearch_domain.monitoring.endpoint} \
        --username ${var.opensearch_master_user} \
        --password ${var.opensearch_master_password} \
        --dashboard-file ${local.dashboard_file}
    EOT
  }
}