# What this module reads but does not own. The network, the API, the database
# and the site are still CloudFormation stacks (infra/backend.yaml,
# infra/frontend.yaml); Terraform reads their parameters and outputs instead of
# a deploy script passing them in.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

data "aws_cloudformation_stack" "backend" {
  name = "${var.project_name}-backend"
}

data "aws_cloudformation_stack" "frontend" {
  name = "${var.project_name}-frontend"
}

# The API function: the builder and the parser run its image with another command.
data "aws_lambda_function" "api" {
  function_name = data.aws_cloudformation_stack.backend.outputs["FunctionName"]
}

# The API's security group: the database already accepts connections from it,
# so the builder needs no new rule. Not a stack output - found by its CloudFormation tags.
data "aws_security_group" "backend_function" {
  vpc_id = local.vpc_id

  tags = {
    "aws:cloudformation:stack-name" = data.aws_cloudformation_stack.backend.name
    "aws:cloudformation:logical-id" = "FunctionSecurityGroup"
  }
}

# The builder has no route to Secrets Manager (no NAT), so it gets the
# connection string as an environment variable, like the API. Reading it here
# puts it in the state: see docs/decisions/0005-terraform.md.
data "aws_secretsmanager_secret_version" "database_url" {
  secret_id = data.aws_cloudformation_stack.backend.outputs["DatabaseUrlSecretArn"]
}

# Route tables of the builder's subnets: their own, else the VPC's main one.
data "aws_route_tables" "subnets" {
  vpc_id = local.vpc_id

  filter {
    name   = "association.subnet-id"
    values = local.subnet_ids
  }
}

data "aws_route_tables" "main" {
  vpc_id = local.vpc_id

  filter {
    name   = "association.main"
    values = ["true"]
  }
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
  partition  = data.aws_partition.current.partition

  vpc_id       = data.aws_cloudformation_stack.backend.parameters["VpcId"]
  subnet_ids   = split(",", data.aws_cloudformation_stack.backend.parameters["SubnetIds"])
  architecture = data.aws_cloudformation_stack.backend.parameters["Architecture"]
  image_uri    = data.aws_lambda_function.api.image_uri

  route_table_ids = length(data.aws_route_tables.subnets.ids) > 0 ? data.aws_route_tables.subnets.ids : data.aws_route_tables.main.ids

  # Every origin the site is served from, plus Vite's dev server.
  site_origins = compact([
    var.app_domain_name != "" ? "https://${var.app_domain_name}" : "",
    "https://${data.aws_cloudformation_stack.frontend.outputs["DistributionDomainName"]}",
    "http://localhost:${var.frontend_port}",
  ])
}
