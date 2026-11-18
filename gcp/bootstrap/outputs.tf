# What to paste into the spry-gcp workspace's environment variables.

output "TFC_GCP_PROVIDER_AUTH" {
  value = "true"
}

output "TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL" {
  value = google_service_account.terraform.email
}

output "TFC_GCP_WORKLOAD_PROVIDER_NAME" {
  value = google_iam_workload_identity_pool_provider.hcp_terraform.name
}

# For a GitHub Actions workflow (google-github-actions/auth): workload_identity_provider.
output "github_workload_identity_provider" {
  value = google_iam_workload_identity_pool_provider.github.name
}

output "api_service_account_email" {
  value = google_service_account.api.email
}

output "project_number" {
  value = data.google_project.this.number
}
