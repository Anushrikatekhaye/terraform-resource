terraform {
  # use_lockfile (S3 native state locking) needs Terraform 1.10 or newer
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # Remote state in S3 with native lockfile locking (no DynamoDB table needed).
  # Backend blocks cannot use variables, so the bucket name is passed at init time:
  #   terraform init -backend-config="bucket=<your-state-bucket>"
  # See README section "Remote state" for creating the bucket.
  backend "s3" {
    key          = "nlb-demo/dev/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  # Applied automatically to every taggable resource
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
    }
  }
}
