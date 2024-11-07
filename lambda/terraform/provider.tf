terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

provider "aws" {
  region = "eu-west-1"

  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "Lambda-Monitoring"
      ManagedBy   = "Terraform"
    }
  }
}