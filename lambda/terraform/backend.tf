terraform {
  backend "s3" {
    bucket = "kenbi-dev-terraform-tf-tfstates"
    key    = "terraform/dev/opensearch-monitoring/lambda/terraform/terraform.tfstate"
    region = "eu-west-1"
  }
}
