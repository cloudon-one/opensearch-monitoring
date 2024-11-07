resource "aws_opensearch_domain" "monitoring" {
  domain_name    = "${var.function_name}-monitoring"
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
    subnet_ids         = [var.vpc_subnet_ids[0]]  # Using first subnet for single-AZ deployment
    security_group_ids = [aws_security_group.opensearch.id]
  }

  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action = "es:*"
        Resource = "${aws_opensearch_domain.monitoring.arn}/*"
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
  subnet_id     = var.vpc_subnet_ids[0]  # Use the first subnet as the public subnet

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