# -----------------------------------------------------------------------------
# provider.tf - Terraform settings, remote state backend and AWS provider
# -----------------------------------------------------------------------------

terraform {
  # S3 native state locking (use_lockfile) needs Terraform 1.10 or newer.
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.90.0, < 7.0.0"
    }
  }

  # Remote state in S3 with a native lockfile (no DynamoDB table required).
  #
  # The bucket name and region are NOT hardcoded so that no account-specific
  # values live in Git. They are supplied at init time:
  #
  #   ./scripts/bootstrap-state.sh            # creates the bucket + backend.hcl
  #   terraform init -backend-config=backend.hcl
  #
  # Want to try the project with local state first? Comment out this whole
  # backend block and run a plain `terraform init`.
  backend "s3" {
    key          = "aws-nlb-autoscaling/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  # Every taggable resource created by this provider gets these tags.
  # (Instances launched by the ASG are tagged separately - see launch_template.tf.)
  default_tags {
    tags = local.common_tags
  }
}
