terraform {
  backend "s3" {
    bucket = ""
    key    = "terraform/terraform.tfstate"
    region = "us-east-2"
  }
}
