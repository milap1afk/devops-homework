terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  # backend "s3" { bucket = "milap-tf-state", key = "final/terraform.tfstate", region = "ap-south-1", use_lockfile = true }
}

provider "aws" {
  region                      = var.region
  skip_credentials_validation = var.offline_plan
  skip_requesting_account_id  = var.offline_plan
  skip_metadata_api_check     = var.offline_plan
  default_tags {
    tags = { Project = "kirana-final", ManagedBy = "terraform", Environment = var.environment }
  }
}
