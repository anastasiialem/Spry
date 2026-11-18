# One-time bootstrap of the Google Cloud project, applied once from a laptop
# with your own account (gcloud auth application-default login), local state.
#
# It creates what the main gcp/ configuration cannot create for itself:
#   - the Terraform service account, with only the roles that configuration needs;
#   - the API's runtime service account (creating service accounts and granting
#     project-level roles would otherwise need IAM admin on the Terraform account);
#   - Workload Identity Federation, so HCP Terraform (and, optionally, GitHub
#     Actions) act as the Terraform service account with short-lived tokens.
# No service account key is created anywhere.

terraform {
  required_version = ">= 1.10"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
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

data "google_project" "this" {}

resource "google_project_service" "bootstrap" {
  for_each = toset([
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
  ])

  service            = each.key
  disable_on_destroy = false
}

# --- the Terraform service account -------------------------------------------

resource "google_service_account" "terraform" {
  account_id   = "${var.project_name}-terraform"
  display_name = "Terraform (gcp/ via HCP Terraform)"
  depends_on   = [google_project_service.bootstrap]
}

# The roles the lab lists, plus Firebase Hosting for the site. No Owner, no Editor.
resource "google_project_iam_member" "terraform" {
  for_each = toset([
    "roles/run.admin",
    "roles/cloudsql.admin",
    "roles/artifactregistry.admin",
    "roles/secretmanager.admin",
    "roles/serviceusage.serviceUsageAdmin",
    "roles/iam.serviceAccountUser",
    "roles/firebasehosting.admin",
  ])

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.terraform.email}"
}

# --- the API's own identity --------------------------------------------------

resource "google_service_account" "api" {
  account_id   = "${var.project_name}-api"
  display_name = "Spry API on Cloud Run"
  depends_on   = [google_project_service.bootstrap]
}

# Cloud SQL Client is a project-level role. Secret access is granted per secret
# in gcp/, so the API can read its own secret and nothing else.
resource "google_project_iam_member" "api_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.api.email}"
}

# --- Workload Identity Federation ---------------------------------------------

resource "google_iam_workload_identity_pool" "ci" {
  workload_identity_pool_id = "${var.project_name}-ci"
  display_name              = "Spry CI"
  description               = "HCP Terraform and GitHub Actions, no stored keys"
  depends_on                = [google_project_service.bootstrap]
}

# HCP Terraform presents an OIDC token per run phase. Only runs of the one
# workspace, in the one organization, identified by their immutable ids.
resource "google_iam_workload_identity_pool_provider" "hcp_terraform" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.ci.workload_identity_pool_id
  workload_identity_pool_provider_id = "hcp-terraform"
  display_name                       = "HCP Terraform"

  oidc {
    issuer_uri = "https://app.terraform.io"
  }

  attribute_mapping = {
    "google.subject"                        = "assertion.sub"
    "attribute.terraform_organization_id"   = "assertion.terraform_organization_id"
    "attribute.terraform_workspace_id"      = "assertion.terraform_workspace_id"
    "attribute.terraform_run_phase"         = "assertion.terraform_run_phase"
    "attribute.terraform_organization_name" = "assertion.terraform_organization_name"
    "attribute.terraform_workspace_name"    = "assertion.terraform_workspace_name"
  }

  attribute_condition = join(" && ", [
    "assertion.terraform_organization_id == \"${var.hcp_organization_id}\"",
    "assertion.terraform_workspace_id == \"${var.hcp_workspace_id}\"",
  ])
}

resource "google_service_account_iam_member" "hcp_terraform" {
  service_account_id = google_service_account.terraform.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.ci.name}/attribute.terraform_workspace_id/${var.hcp_workspace_id}"
}

# GitHub Actions (stretch: deploy the image from CI). Numeric repository and
# owner ids: a name can be deleted and re-registered by someone else.
resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.ci.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub Actions"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository_id"    = "assertion.repository_id"
    "attribute.repository_owner" = "assertion.repository_owner_id"
    "attribute.ref"              = "assertion.ref"
  }

  attribute_condition = join(" && ", [
    "assertion.repository_owner_id == \"${var.github_owner_id}\"",
    "assertion.repository_id == \"${var.github_repository_id}\"",
  ])
}

resource "google_service_account_iam_member" "github" {
  service_account_id = google_service_account.terraform.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.ci.name}/attribute.repository_id/${var.github_repository_id}"
}
