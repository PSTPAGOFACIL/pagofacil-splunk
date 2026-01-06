provider "aws" {
  region = "us-west-2"
}

terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket  = "pagofacil-splunk-tf-backend-dev"
    key     = "dev"
    encrypt = true
    region  = "us-west-2"
  }
}