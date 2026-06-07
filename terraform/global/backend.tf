terraform {
  backend "s3" {
    key            = "global/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "saaf-uw-tfstate-locks"
    encrypt        = true
  }
}
