terraform {
  backend "s3" {
    bucket = "cloudon-aws-admin-tf-state-010"
    key    = "opensearch-monitoring/lambda/terraform/terraform.tfstate"
    region = "us-east-2"
  }
}
