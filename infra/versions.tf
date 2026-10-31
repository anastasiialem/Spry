terraform {
  # State and runs live in HCP Terraform: Remote execution, dynamic AWS
  # credentials (TFC_AWS_PROVIDER_AUTH / TFC_AWS_RUN_ROLE_ARN), VCS-driven -
  # a pull request gets a plan, a merge to main applies it.
  cloud {
    organization = "ooad-anastasiialem"

    workspaces {
      name = "spry-dev"
    }
  }

  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      PROJECT_NAME = var.project_name
      ManagedBy    = "terraform"
    }
  }
}
