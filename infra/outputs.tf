# Everything the scripts and the frontend build read: terraform output -raw <name>.

# --- sign-in -------------------------------------------------------------------

output "user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "client_id" {
  value = aws_cognito_user_pool_client.web.id
}

output "managed_login_branding_id" {
  value = aws_cognito_managed_login_branding.web.managed_login_branding_id
}

# What oidc-client-ts calls the authority: discovery lives under it.
output "authority" {
  value = "https://cognito-idp.${local.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
}

# The managed login / logout host.
output "domain" {
  value = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${local.region}.amazoncognito.com"
}

output "google_redirect_uri" {
  description = "Paste into the Google OAuth client as the authorised redirect URI."
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${local.region}.amazoncognito.com/oauth2/idpresponse"
}

# --- weekly report -------------------------------------------------------------

output "reports_bucket" {
  value = aws_s3_bucket.reports.id
}

output "report_queue_url" {
  value = aws_sqs_queue.requests.url
}

output "report_dlq_url" {
  value = aws_sqs_queue.requests_dlq.url
}

output "report_sender" {
  value = local.sender
}

# The three CNAMEs SES needs for DKIM: name -> value.
output "dkim_records" {
  value = {
    for t in aws_sesv2_email_identity.domain.dkim_signing_attributes[0].tokens :
    "${t}._domainkey.${var.mail_domain}" => "${t}.dkim.amazonses.com"
  }
}

# --- paste an agenda -------------------------------------------------------------

output "parser_url" {
  description = "What the frontend calls for \"Paste an agenda\" (VITE_PARSER_URL)."
  value       = trimsuffix(aws_lambda_function_url.parser.function_url, "/")
}

output "parser_model" {
  value = var.parser_model
}
