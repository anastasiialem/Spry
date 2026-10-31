# Non-secret values only. google_client_secret is a sensitive variable in the
# HCP Terraform workspace (or TF_VAR_google_client_secret on a laptop).

project_name = "spry"
region       = "us-east-1"

# sign-in
cognito_domain_prefix = "spry-anastasiia"
google_client_id      = "324008245985-d7fhqqdc8p8jslgrkv7jogcc8201it7v.apps.googleusercontent.com"
app_domain_name       = "app.spry.pp.ua"

# weekly report
mail_domain       = "spry.pp.ua"
report_recipients = "lem.pn@ucu.edu.ua"

# paste an agenda
allowed_origins = [
  "https://app.spry.pp.ua",
  "https://dwpif3yujzq45.cloudfront.net",
  "http://localhost:5173",
]
budget_email = "lem.pn@ucu.edu.ua"
