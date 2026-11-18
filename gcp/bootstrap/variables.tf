variable "project_id" {
  type        = string
  description = "The Google Cloud project id: permanent, 6-30 chars, never reusable."
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "project_name" {
  type    = string
  default = "spry"
}

variable "hcp_organization_id" {
  type        = string
  description = "HCP Terraform organization id (org-...), Settings -> General. Not the name."
}

variable "hcp_workspace_id" {
  type        = string
  description = "Id of the spry-gcp workspace (ws-...), its Settings -> General. Not the name."
}

variable "github_owner_id" {
  type        = string
  description = "gh api repos/<owner>/<repo> --jq .owner.id"
}

variable "github_repository_id" {
  type        = string
  description = "gh api repos/<owner>/<repo> --jq .id"
}
