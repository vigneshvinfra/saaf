terraform {
  # Remote state created by terraform/bootstrap. The bucket name embeds the
  # account ID, so it is supplied at init time rather than hardcoded:
  #   terraform init -backend-config="bucket=saaf-uw-tfstate-<account-id>"
  backend "s3" {
    key            = "staging/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "saaf-uw-tfstate-locks"
    encrypt        = true
  }
}
