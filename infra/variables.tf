# Inputs of the root module. Non-secret values are in terraform.tfvars (in Git);
# secrets are sensitive variables set in the HCP Terraform workspace, never here.
# What earlier CloudFormation stacks already know (VPC, subnets, image, database
# URL, the site's CloudFront host) is read in data.tf, not typed in.

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type        = string
  default     = "spry"
  description = "Prefix of every name, and the PROJECT_NAME tag on every resource."
}

# --- sign-in (was infra/auth.yaml) -------------------------------------------

variable "cognito_domain_prefix" {
  type        = string
  description = "https://<prefix>.auth.<region>.amazoncognito.com. May not contain aws, amazon or cognito."

  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$", var.cognito_domain_prefix))
    error_message = "Lowercase letters, digits and hyphens; must start and end with a letter or digit."
  }
}

variable "google_client_id" {
  type        = string
  description = "OAuth client ID of a \"Web application\" client in Google Cloud."
}

variable "google_client_secret" {
  type        = string
  sensitive   = true
  description = "Its secret. A sensitive variable in the HCP Terraform workspace; never in a file."
}

variable "app_domain_name" {
  type        = string
  default     = ""
  description = "The site's custom domain (app.example.com). Empty: only the CloudFront host and localhost."
}

variable "frontend_port" {
  type        = number
  default     = 5173
  description = "Vite's dev server port: localhost may sign in too."
}

# --- weekly report (was infra/reports.yaml) ----------------------------------

variable "create_s3_endpoint" {
  type        = bool
  default     = true
  description = "false when the VPC already has an S3 gateway endpoint on these route tables."
}

variable "mail_domain" {
  type        = string
  description = "The sender is reports@<this>. Verified in SES with DKIM (three CNAMEs)."
}

variable "sender_address" {
  type        = string
  default     = ""
  description = "Empty: reports@<mail_domain>. Any other SES-verified address, while DKIM is pending."
}

variable "report_recipients" {
  type        = string
  description = "Comma-separated. In the SES sandbox the first one is created as an identity here."
}

variable "schedule_expression" {
  type        = string
  default     = "cron(0 7 ? * MON *)"
  description = "Monday 07:00 in schedule_timezone. For a test run, rate(5 minutes) - then set it back."
}

variable "schedule_timezone" {
  type    = string
  default = "Europe/Kyiv"
}

variable "report_fail_week" {
  type        = string
  default     = ""
  description = "Lab exercise: the builder raises for this one week (e.g. 2026-W13). Empty in normal use."
}

variable "log_retention_days" {
  type    = number
  default = 14
}

# --- paste an agenda (was infra/ai.yml) --------------------------------------

variable "parser_model" {
  type        = string
  default     = "mistral.mistral-large-3-675b-instruct"
  description = "Bedrock model id with tool use (Converse API). See docs/agenda-parser-answers.md."
}

variable "allowed_origins" {
  type        = list(string)
  description = "The site's origins, for the parser function URL's CORS."
}

variable "budget_email" {
  type        = string
  default     = ""
  description = "Who gets the budget alarm. Empty: no budget."
}

variable "budget_limit_usd" {
  type    = number
  default = 5
}
