# Spry weekly meetings report (was infra/reports.yaml, Lab 5), event-driven.
# Every Monday 07:00 Kyiv time EventBridge Scheduler puts a "build the report"
# command on an SQS queue (make report-now does the same on demand). The
# report-builder Lambda - the backend's image, in the VPC next to the database -
# writes reports/<week>.csv to S3 through a free gateway endpoint. S3 announces
# the new file, and the report-mailer Lambda - outside the VPC, so it can reach
# SES - emails it. The builder never calls the mailer; the file is the event.

locals {
  reports_bucket = "${var.project_name}-reports-${local.account_id}"
  sender         = var.sender_address != "" ? var.sender_address : "reports@${var.mail_domain}"
}

# --- network: S3 for a function with no internet ----------------------------

# Without it the builder's PutObject hangs until the timeout: no NAT, so the
# request has nowhere to go. Gateway endpoints cost nothing.
resource "aws_vpc_endpoint" "s3" {
  count = var.create_s3_endpoint ? 1 : 0

  vpc_id            = local.vpc_id
  service_name      = "com.amazonaws.${local.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = local.route_table_ids
}

# --- storage -----------------------------------------------------------------

# In CloudFormation the bucket, the notification and the Lambda permission were
# one resource with a cycle in it, broken by naming the bucket by hand. Here they
# are separate resources, and plain references order them.
resource "aws_s3_bucket" "reports" {
  bucket = local.reports_bucket
}

resource "aws_s3_bucket_public_access_block" "reports" {
  bucket = aws_s3_bucket.reports.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    id     = "expire-reports"
    status = "Enabled"

    filter {
      prefix = "reports/"
    }

    expiration {
      days = 90
    }
  }
}

resource "aws_s3_bucket_notification" "reports" {
  bucket = aws_s3_bucket.reports.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.report_mailer.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "reports/"
    filter_suffix       = ".csv"
  }

  depends_on = [aws_lambda_permission.mailer_from_s3]
}

# --- queue -------------------------------------------------------------------

resource "aws_sqs_queue" "requests_dlq" {
  name                      = "${var.project_name}-report-requests-dlq"
  message_retention_seconds = 1209600 # 14 days to notice and redrive
  max_message_size          = 1048576 # what SQS creates today; the provider still assumes 256 KiB
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "requests" {
  name = "${var.project_name}-report-requests"
  # 6 x the builder's 60 s timeout. Shorter, and a message reappears while the
  # first attempt still runs: a second builder starts on the same report.
  visibility_timeout_seconds = 360
  message_retention_seconds  = 345600  # 4 days
  max_message_size           = 1048576 # see the DLQ
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.requests_dlq.arn
    maxReceiveCount     = 3
  })
}

# --- trigger 1: the schedule --------------------------------------------------

resource "aws_iam_role" "scheduler" {
  name = "${var.project_name}-reports-SchedulerRole-NxApH0pwq2gZ"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account_id }
      }
    }]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  name = "send-report-request"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.requests.arn
    }]
  })
}

resource "aws_scheduler_schedule" "weekly" {
  name                         = "${var.project_name}-weekly-report"
  description                  = "Monday morning - ask for last week's report"
  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = var.schedule_timezone
  state                        = "ENABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_sqs_queue.requests.arn
    role_arn = aws_iam_role.scheduler.arn
    # A command. No week: the builder takes the previous ISO week.
    input = "{\"week\": null, \"source\": \"schedule\"}"

    retry_policy {
      maximum_retry_attempts = 3
    }
  }
}

# --- trigger 2: the builder, fed by the queue ---------------------------------

resource "aws_iam_role" "builder" {
  name = "${var.project_name}-reports-BuilderRole-jCHL6B3VRrPY"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Logs + network interfaces in the VPC; receive/delete from SQS.
resource "aws_iam_role_policy_attachment" "builder" {
  for_each = toset([
    "service-role/AWSLambdaVPCAccessExecutionRole",
    "service-role/AWSLambdaSQSQueueExecutionRole",
  ])

  role       = aws_iam_role.builder.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/${each.key}"
}

resource "aws_iam_role_policy" "builder" {
  name = "write-reports"
  role = aws_iam_role.builder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "s3:PutObject"
      Resource = "${aws_s3_bucket.reports.arn}/reports/*"
    }]
  })
}

resource "aws_cloudwatch_log_group" "builder" {
  name              = "/aws/lambda/${var.project_name}-report-builder"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "report_builder" {
  function_name = "${var.project_name}-report-builder"
  description   = "Builds reports/<week>.csv from the database"
  package_type  = "Image"
  image_uri     = local.image_uri
  architectures = [local.architecture]
  memory_size   = 512
  # A cold start, a database connect and a few queries; the queue's visibility
  # timeout above is 6 x this.
  timeout = 60
  role    = aws_iam_role.builder.arn

  image_config {
    command = ["app.reports.lambda_handler.handler"]
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.builder.name
  }

  vpc_config {
    subnet_ids         = local.subnet_ids
    security_group_ids = [data.aws_security_group.backend_function.id]
  }

  environment {
    variables = {
      APP_ENV          = "production"
      DB_POOLING       = "false"
      DATABASE_URL     = data.aws_secretsmanager_secret_version.database_url.secret_string
      REPORTS_BUCKET   = aws_s3_bucket.reports.id
      REPORT_TIMEZONE  = var.schedule_timezone
      REPORT_FAIL_WEEK = var.report_fail_week
    }
  }

  # The application pipeline (make deploy-backend) rolls the image on every
  # push to main. Terraform sets it once and then leaves it to the pipeline.
  lifecycle {
    ignore_changes = [image_uri]
  }
}

# The Lambda service polls the queue and invokes the builder: the function
# itself never connects to SQS, which is why it works with no NAT.
resource "aws_lambda_event_source_mapping" "builder_queue" {
  event_source_arn = aws_sqs_queue.requests.arn
  function_name    = aws_lambda_function.report_builder.arn
  batch_size       = 1
  enabled          = true
}

# --- trigger 3: the mailer, fed by S3 -----------------------------------------

resource "aws_iam_role" "mailer" {
  name = "${var.project_name}-reports-MailerRole-BLIyyBxFREsp"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "mailer_basic" {
  role       = aws_iam_role.mailer.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "mailer" {
  name = "read-and-mail"
  role = aws_iam_role.mailer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Read only: it must never write into reports/ (it would trigger itself).
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.reports.arn}/reports/*"
      },
      {
        Effect   = "Allow"
        Action   = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource = "arn:${local.partition}:ses:${local.region}:${local.account_id}:identity/*"
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "mailer" {
  name              = "/aws/lambda/${var.project_name}-report-mailer"
  retention_in_days = var.log_retention_days
}

data "archive_file" "report_mailer" {
  type        = "zip"
  source_file = "${path.module}/lambda/report_mailer/index.py"
  output_path = "${path.module}/.build/report_mailer.zip"
}

resource "aws_lambda_function" "report_mailer" {
  function_name    = "${var.project_name}-report-mailer"
  description      = "Emails a new report through SES (outside the VPC)"
  runtime          = "python3.13"
  architectures    = ["arm64"]
  handler          = "index.handler"
  memory_size      = 128
  timeout          = 30
  role             = aws_iam_role.mailer.arn
  filename         = data.archive_file.report_mailer.output_path
  source_code_hash = data.archive_file.report_mailer.output_base64sha256

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.mailer.name
  }

  environment {
    variables = {
      SENDER     = "Spry reports <${local.sender}>"
      RECIPIENTS = var.report_recipients
    }
  }
}

resource "aws_lambda_permission" "mailer_from_s3" {
  statement_id   = "${var.project_name}-reports-MailerInvokePermission-tka4VOxpJQEJ"
  function_name  = aws_lambda_function.report_mailer.function_name
  action         = "lambda:InvokeFunction"
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.reports.arn
  source_account = local.account_id
}

# --- email ----------------------------------------------------------------------

# The sending domain. Verified once its three DKIM CNAMEs are in DNS (nic.ua).
resource "aws_sesv2_email_identity" "domain" {
  email_identity = var.mail_domain

  dkim_signing_attributes {
    next_signing_key_length = "RSA_2048_BIT"
  }
}

# The SES sandbox delivers only to verified addresses: this sends the first
# recipient a "please confirm" email.
resource "aws_sesv2_email_identity" "recipient" {
  email_identity = trimspace(split(",", var.report_recipients)[0])
}
