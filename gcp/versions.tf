terraform {
  # Its own HCP Terraform workspace, separate from infra/'s spry-dev: one plan
  # can never touch both clouds. Credentials: TFC_GCP_PROVIDER_AUTH +
  # TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL + TFC_GCP_WORKLOAD_PROVIDER_NAME
  # (Workload Identity Federation, from gcp/bootstrap). No key file.
  cloud {
    organization = "ooad-anastasiialem"

    workspaces {
      name = "spry-gcp"
    }
  }

  required_version = ">= 1.10"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region

  default_labels = {
    project    = var.project_name
    managed-by = "terraform"
  }
}
