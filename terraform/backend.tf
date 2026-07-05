terraform {
  backend "s3" {
    bucket         = "victoriametrics-tfstate-bucket"
    key            = "terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "victoriametrics-tfstate-locks"
    encrypt        = true
  }
}