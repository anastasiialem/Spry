# Spry sign-in (was infra/auth.yaml, Lab 4): a Cognito user pool with Cognito's
# managed login (email + password, self sign-up on), federated to Google. The
# frontend is a public client (no secret) using the authorization-code flow
# with PKCE. Cost: the Essentials tier is free up to 10,000 monthly active users.

resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-users"

  # People sign in with their email; there is no separate username.
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  username_configuration {
    case_sensitive = false
  }

  # Self sign-up stays on, so anyone (the lecturer too) can create an account.
  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = false
    temporary_password_validity_days = 7
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Required attributes are asked on the managed sign-up form. Changing this
  # list REPLACES THE POOL, and every account in it is gone.
  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = "0"
      max_length = "2048"
    }
  }

  schema {
    name                = "preferred_username"
    attribute_data_type = "String"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = "0"
      max_length = "2048"
    }
  }

  # Managed login (version 2) needs Essentials; the first 10,000 MAU are free.
  user_pool_tier      = "ESSENTIALS"
  deletion_protection = "INACTIVE"

  # One person, one account: see aws_lambda_function.link_accounts.
  lambda_config {
    pre_sign_up = aws_lambda_function.link_accounts.arn
  }
}

# Pre sign-up trigger. Without it "Sign in with Google" and email + password
# with the same address are two users with two different `sub`s - and two
# different calendars.
#   - Google sign-in, first time, and a verified password account with that
#     email exists -> link Google to it (same sub, same meetings).
#   - Password sign-up for an email that already signs in with Google ->
#     refused with a hint, instead of creating a second account.
data "archive_file" "link_accounts" {
  type        = "zip"
  source_file = "${path.module}/lambda/link_accounts/index.py"
  output_path = "${path.module}/.build/link_accounts.zip"
}

resource "aws_lambda_function" "link_accounts" {
  function_name    = "${var.project_name}-link-accounts"
  runtime          = "python3.13"
  architectures    = ["arm64"]
  handler          = "index.handler"
  timeout          = 10
  memory_size      = 128
  role             = aws_iam_role.link_accounts.arn
  filename         = data.archive_file.link_accounts.output_path
  source_code_hash = data.archive_file.link_accounts.output_base64sha256
}

resource "aws_iam_role" "link_accounts" {
  # The name CloudFormation generated; kept, so the role is imported, not replaced.
  name = "${var.project_name}-auth-LinkAccountsRole-v0ycK2CwmGbN"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "link_accounts_basic" {
  role       = aws_iam_role.link_accounts.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "link_accounts" {
  name = "link-accounts"
  role = aws_iam_role.link_accounts.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      # Pool ARN by pattern: naming the pool itself would be a cycle
      # (the pool needs this function first).
      Effect = "Allow"
      Action = [
        "cognito-idp:ListUsers",
        "cognito-idp:AdminLinkProviderForUser",
      ]
      Resource = "arn:${local.partition}:cognito-idp:${local.region}:${local.account_id}:userpool/*"
    }]
  })
}

resource "aws_lambda_permission" "link_accounts" {
  statement_id  = "${var.project_name}-auth-LinkAccountsPermission-46Uqz5Ep5pTr"
  function_name = aws_lambda_function.link_accounts.function_name
  action        = "lambda:InvokeFunction"
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.main.arn
}

resource "aws_cognito_identity_provider" "google" {
  user_pool_id  = aws_cognito_user_pool.main.id
  provider_name = "Google"
  provider_type = "Google"

  provider_details = {
    client_id        = var.google_client_id
    client_secret    = var.google_client_secret
    authorize_scopes = "openid email profile"
  }

  # Without this a Google user lands in the pool with no email.
  attribute_mapping = {
    email          = "email"
    email_verified = "email_verified"
    name           = "name"
    # Required in this pool, so a Google user needs one too: their Google name.
    preferred_username = "name"
    username           = "sub"
  }

  # Cognito adds read-only details of its own (the discovery URLs, ...).
  lifecycle {
    ignore_changes = [
      provider_details["attributes_url"],
      provider_details["attributes_url_add_attributes"],
      provider_details["authorize_url"],
      provider_details["oidc_issuer"],
      provider_details["token_request_method"],
      provider_details["token_url"],
    ]
  }
}

resource "aws_cognito_user_pool_client" "web" {
  name         = "${var.project_name}-web"
  user_pool_id = aws_cognito_user_pool.main.id

  # Public client: a browser cannot keep a secret, so it gets none (generate_secret
  # is left unset: it is not read back on import, and setting it would force a
  # replacement). PKCE protects the code exchange instead.
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  # A reference, not the string "Google": the client is created after the provider.
  supported_identity_providers = ["COGNITO", aws_cognito_identity_provider.google.provider_name]

  # Exact URLs, trailing slash included: the frontend sends
  # redirect_uri = <origin>/auth/callback/ and logout_uri = <origin>/login/.
  callback_urls = [for o in local.site_origins : "${o}/auth/callback/"]
  logout_urls   = flatten([for o in local.site_origins : ["${o}/", "${o}/login/"]])

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  # "No such user" and "wrong password" look the same to a stranger.
  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true

  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  user_pool_id          = aws_cognito_user_pool.main.id
  domain                = var.cognito_domain_prefix
  managed_login_version = 2
}

# Without a branding style a version-2 domain has no sign-in page. Created from
# Cognito's defaults; `make auth-branding` then adds the page background image
# through the API, so Terraform leaves the settings and assets alone.
resource "aws_cognito_managed_login_branding" "web" {
  user_pool_id                = aws_cognito_user_pool.main.id
  client_id                   = aws_cognito_user_pool_client.web.id
  use_cognito_provided_values = true

  lifecycle {
    ignore_changes = [use_cognito_provided_values, settings, asset]
  }

  depends_on = [aws_cognito_user_pool_domain.main]
}
