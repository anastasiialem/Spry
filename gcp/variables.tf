variable "project_id" {
  type        = string
  description = "The Google Cloud project id (same as in bootstrap/)."
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "project_name" {
  type    = string
  default = "spry"
}

# --- database ------------------------------------------------------------------

variable "db_tier" {
  type        = string
  default     = "db-f1-micro"
  description = "Shared core, 0.6 GB: $0.0105/h while running."
}

variable "db_activation_policy" {
  type        = string
  default     = "ALWAYS"
  description = "ALWAYS = running. NEVER = stopped: compute stops billing, the 10 GB disk still does."

  validation {
    condition     = contains(["ALWAYS", "NEVER"], var.db_activation_policy)
    error_message = "ALWAYS or NEVER."
  }
}

# --- API -------------------------------------------------------------------------

variable "api_image" {
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
  description = <<-EOT
    Only the first deploy uses this: Google's hello container, so the service can
    exist before our image is pushed. After that make gcp-deploy-backend rolls the
    image and Terraform ignores it (as infra/ does with the Lambda image).
  EOT
}

variable "api_max_instances" {
  type        = number
  default     = 1
  description = "db-f1-micro allows ~25 connections; one instance pools at most 15."
}

# Sign-in stays on AWS (Cognito) for now: the API on Cloud Run checks the same
# access tokens. Values from `make infra-output`.
variable "cognito_region" {
  type    = string
  default = "us-east-1"
}

variable "cognito_user_pool_id" {
  type    = string
  default = ""
}

variable "cognito_client_id" {
  type    = string
  default = ""
}
