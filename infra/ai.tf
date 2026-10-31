# Spry "Paste an agenda" (was infra/ai.yml, Lab 6). The agenda-parser Lambda -
# the backend's image with another command - sits behind its own public
# function URL, outside the VPC: pasted text -> a model on Amazon Bedrock
# (Mistral Large 3) -> validated agenda JSON. It never touches the database.
# Also a monthly AWS Budgets alarm, because every parse costs money.

resource "aws_iam_role" "parser" {
  name = "${var.project_name}-ai-ParserRole-21xOyYCeA0ZN"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "parser_basic" {
  role       = aws_iam_role.parser.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# No API key anywhere: this permission is what lets the function call the
# model (Converse is authorised as InvokeModel). Any foundation model in this
# region, so parser_model can change without a policy change.
resource "aws_iam_role_policy" "parser" {
  name = "call-bedrock-model"
  role = aws_iam_role.parser.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "bedrock:InvokeModel"
      Resource = "arn:aws:bedrock:${local.region}::foundation-model/*"
    }]
  })
}

resource "aws_cloudwatch_log_group" "parser" {
  name              = "/aws/lambda/${var.project_name}-agenda-parser"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "agenda_parser" {
  function_name = "${var.project_name}-agenda-parser"
  description   = "Pasted text -> Bedrock model -> validated agenda JSON (outside the VPC)"
  package_type  = "Image"
  image_uri     = local.image_uri
  architectures = [local.architecture]
  memory_size   = 512
  # Up to two model calls (one retry with the validation error), 10 s each.
  timeout = 30
  role    = aws_iam_role.parser.arn

  image_config {
    command = ["app.ai.agenda_lambda.handler"]
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.parser.name
  }

  # No vpc_config: no database here, and outside the VPC it reaches Bedrock and
  # Cognito's public keys with no NAT and no interface endpoint.
  environment {
    variables = {
      APP_ENV              = "production"
      PARSER_MODEL         = var.parser_model
      BEDROCK_REGION       = local.region
      COGNITO_REGION       = local.region
      COGNITO_USER_POOL_ID = aws_cognito_user_pool.main.id
      COGNITO_CLIENT_ID    = aws_cognito_user_pool_client.web.id
    }
  }

  # make deploy-backend rolls the image on every push to main.
  lifecycle {
    ignore_changes = [image_uri]
  }
}

# Public, but the handler rejects anything without a valid Cognito token (401)
# and any text over 10,000 characters (413) before calling the model. CORS
# lives here, so the OPTIONS preflight never reaches the code.
resource "aws_lambda_function_url" "parser" {
  function_name      = aws_lambda_function.agenda_parser.function_name
  authorization_type = "NONE"

  cors {
    allow_origins = var.allowed_origins
    allow_methods = ["POST"]
    allow_headers = ["authorization", "content-type"]
    max_age       = 3600
  }
}

# A public function URL needs both grants, as for the API.
resource "aws_lambda_permission" "parser_url" {
  statement_id           = "${var.project_name}-ai-ParserUrlPermission-W07UneQzZNvf"
  function_name          = aws_lambda_function.agenda_parser.function_name
  action                 = "lambda:InvokeFunctionUrl"
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "parser_url_invoke" {
  statement_id             = "${var.project_name}-ai-ParserUrlInvokePermission-1JTkex3o7ASI"
  function_name            = aws_lambda_function.agenda_parser.function_name
  action                   = "lambda:InvokeFunction"
  principal                = "*"
  invoked_via_function_url = true
}

# The whole account's bill, not only Bedrock, net of credits: the database is
# paid from the sign-up credits, so a gross budget would alarm on day one.
resource "aws_budgets_budget" "monthly" {
  count = var.budget_email != "" ? 1 : 0

  name         = "${var.project_name}-monthly"
  budget_type  = "COST"
  time_unit    = "MONTHLY"
  limit_amount = format("%.1f", var.budget_limit_usd)
  limit_unit   = "USD"

  cost_types {
    include_credit = true
    include_refund = false
  }

  dynamic "notification" {
    for_each = ["ACTUAL", "FORECASTED"]

    content {
      notification_type          = notification.value
      comparison_operator        = "GREATER_THAN"
      threshold                  = 100
      threshold_type             = "PERCENTAGE"
      subscriber_email_addresses = [var.budget_email]
    }
  }
}
