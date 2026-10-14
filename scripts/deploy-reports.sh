#!/usr/bin/env bash
# Deploy the weekly report (infra/reports.yaml): schedule -> SQS -> builder
# Lambda (in the VPC) -> S3 -> mailer Lambda -> SES.
#
# Everything about the network and the database is read from the spry-backend
# stack, so run make deploy-backend first. Needs in .env (gitignored):
#
#   REPORT_RECIPIENTS=you@example.com      who gets the email (first deploy)
#
# Optional:
#   REPORT_MAIL_DOMAIN=spry.pp.ua          defaults to DOMAIN_NAME
#   REPORT_SCHEDULE="rate(5 minutes)"      for a test run; unset = Monday 07:00
#   REPORT_FAIL_WEEK=2026-W13              lab exercise: that week fails -> DLQ
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="${ROOT}/infra/reports.yaml"

log() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m==>\033[0m %s\n' "$*" >&2; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

if [[ -f "${ROOT}/.env" ]]; then
  preset="$(export -p)"
  set -a
  # shellcheck disable=SC1091
  source "${ROOT}/.env"
  set +a
  eval "${preset}"
fi
for var in AWS_PROFILE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN; do
  [[ -n "${!var:-}" ]] || unset "${var}"
done

PROJECT_NAME="${PROJECT_NAME:-spry}"
STACK_NAME="${REPORTS_STACK_NAME:-${PROJECT_NAME}-reports}"
BACKEND_STACK="${STACK_NAME_BACKEND:-${PROJECT_NAME}-backend}"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
export AWS_DEFAULT_REGION="${AWS_REGION}"

aws sts get-caller-identity >/dev/null 2>&1 || die "no usable AWS credentials"

# --- what the backend stack already knows ------------------------------------

backend_param() {
  aws cloudformation describe-stacks --stack-name "${BACKEND_STACK}" \
    --query "Stacks[0].Parameters[?ParameterKey=='$1'].ParameterValue" --output text
}
backend_output() {
  aws cloudformation describe-stacks --stack-name "${BACKEND_STACK}" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}
aws cloudformation describe-stacks --stack-name "${BACKEND_STACK}" >/dev/null 2>&1 \
  || die "no ${BACKEND_STACK} stack - run make deploy-backend first"

VPC_ID="$(backend_param VpcId)"
SUBNET_IDS="$(backend_param SubnetIds)"
ARCHITECTURE="$(backend_param Architecture)"
# The image the API runs right now (CI may have rolled it since the stack's
# parameter was last set).
IMAGE_URI="$(aws lambda get-function --function-name "$(backend_output FunctionName)" \
  --query Code.ImageUri --output text)"
SG_ID="$(aws cloudformation describe-stack-resource --stack-name "${BACKEND_STACK}" \
  --logical-resource-id FunctionSecurityGroup \
  --query StackResourceDetail.PhysicalResourceId --output text)"
DATABASE_URL="$(aws secretsmanager get-secret-value \
  --secret-id "$(backend_output DatabaseUrlSecretArn)" --query SecretString --output text)"
[[ -n "${DATABASE_URL}" ]] || die "could not read the database URL secret"
log "vpc ${VPC_ID}, subnets ${SUBNET_IDS}, sg ${SG_ID}"
log "image ${IMAGE_URI}"

# --- S3 gateway endpoint ------------------------------------------------------

# The route tables the subnets use: their own, or the VPC's main one.
ROUTE_TABLES="$(VPC="${VPC_ID}" SUBNETS="${SUBNET_IDS}" python3 - <<'PY'
import json, os, subprocess

def aws(*a):
    return json.loads(subprocess.check_output(["aws", "ec2", *a, "--output", "json"]))

vpc = os.environ["VPC"]
tables = aws("describe-route-tables", "--filters", f"Name=vpc-id,Values={vpc}")["RouteTables"]
main = next(t["RouteTableId"] for t in tables
            if any(a.get("Main") for a in t.get("Associations", [])))
found = []
for subnet in os.environ["SUBNETS"].split(","):
    own = [t["RouteTableId"] for t in tables
           if any(a.get("SubnetId") == subnet for a in t.get("Associations", []))]
    table = own[0] if own else main
    if table not in found:
        found.append(table)
print(",".join(found))
PY
)"

CREATE_ENDPOINT=true
OURS="$(aws cloudformation describe-stack-resource --stack-name "${STACK_NAME}" \
  --logical-resource-id S3Endpoint --query StackResourceDetail.PhysicalResourceId \
  --output text 2>/dev/null || true)"
EXISTING="$(aws ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=service-name,Values=com.amazonaws.${AWS_REGION}.s3" \
            "Name=vpc-endpoint-type,Values=Gateway" \
  --query 'VpcEndpoints[].VpcEndpointId' --output text)"
for endpoint in ${EXISTING}; do
  if [[ "${endpoint}" != "${OURS}" ]]; then
    CREATE_ENDPOINT=false
    warn "S3 gateway endpoint ${endpoint} already exists in ${VPC_ID} - using it"
  fi
done
log "route tables ${ROUTE_TABLES} (create S3 endpoint: ${CREATE_ENDPOINT})"

# --- email ----------------------------------------------------------------------

MAIL_DOMAIN="${REPORT_MAIL_DOMAIN:-${DOMAIN_NAME:-}}"
[[ -n "${MAIL_DOMAIN}" ]] || die "set REPORT_MAIL_DOMAIN (or DOMAIN_NAME) in .env"
STACK_EXISTS=false
aws cloudformation describe-stacks --stack-name "${STACK_NAME}" >/dev/null 2>&1 && STACK_EXISTS=true
if [[ -z "${REPORT_RECIPIENTS:-}" && "${STACK_EXISTS}" == false ]]; then
  die "set REPORT_RECIPIENTS=you@example.com in .env (who gets the weekly report)"
fi

# --- deploy -----------------------------------------------------------------------

PARAMS_FILE="$(mktemp)"; chmod 600 "${PARAMS_FILE}"
trap 'rm -f "${PARAMS_FILE}"' EXIT

PROJECT_NAME="${PROJECT_NAME}" VPC_ID="${VPC_ID}" SUBNET_IDS="${SUBNET_IDS}" SG_ID="${SG_ID}" \
IMAGE_URI="${IMAGE_URI}" ARCHITECTURE="${ARCHITECTURE}" DATABASE_URL="${DATABASE_URL}" \
CREATE_ENDPOINT="${CREATE_ENDPOINT}" ROUTE_TABLES="${ROUTE_TABLES}" MAIL_DOMAIN="${MAIL_DOMAIN}" \
RECIPIENTS="${REPORT_RECIPIENTS:-}" SCHEDULE="${REPORT_SCHEDULE:-cron(0 7 ? * MON *)}" \
FAIL_WEEK="${REPORT_FAIL_WEEK:-}" \
python3 - "${PARAMS_FILE}" <<'PY'
import json, os, sys
e = os.environ
params = {
    "ProjectName": e["PROJECT_NAME"],
    "VpcId": e["VPC_ID"],
    "SubnetIds": e["SUBNET_IDS"],
    "FunctionSecurityGroupId": e["SG_ID"],
    "ImageUri": e["IMAGE_URI"],
    "Architecture": e["ARCHITECTURE"],
    "DatabaseUrl": e["DATABASE_URL"],
    "CreateS3Endpoint": e["CREATE_ENDPOINT"],
    "RouteTableIds": e["ROUTE_TABLES"],
    "MailDomain": e["MAIL_DOMAIN"],
    "ReportRecipients": e["RECIPIENTS"],
    "ScheduleExpression": e["SCHEDULE"],
    # Always passed, empty included: leaving it out would keep a failure on.
    "ReportFailWeek": e["FAIL_WEEK"],
}
out = [{"ParameterKey": k, "ParameterValue": v} for k, v in params.items()
       if v != "" or k == "ReportFailWeek"]
# Not given (empty): `cloudformation deploy` keeps the stack's current value.
json.dump(out, open(sys.argv[1], "w"))
PY

log "deploying ${STACK_NAME} (schedule: ${REPORT_SCHEDULE:-cron(0 7 ? * MON *)})"
if ! aws cloudformation deploy \
  --stack-name "${STACK_NAME}" \
  --template-file "${TEMPLATE}" \
  --parameter-overrides "file://${PARAMS_FILE}" \
  --capabilities CAPABILITY_IAM \
  --no-fail-on-empty-changeset \
  --tags "PROJECT_NAME=${PROJECT_NAME}"; then
  warn "deploy failed - most recent failure reasons:"
  aws cloudformation describe-stack-events --stack-name "${STACK_NAME}" --max-items 40 \
    --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`||ResourceStatus==`UPDATE_FAILED`].[LogicalResourceId,ResourceStatusReason]' \
    --output table >&2 || true
  exit 1
fi

out() {
  aws cloudformation describe-stacks --stack-name "${STACK_NAME}" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

# --- what is left to do by hand ---------------------------------------------------

relative() { local n="${1%.}"; printf '%s' "${n%."${MAIL_DOMAIN}"}"; }

echo
echo "  bucket      $(out BucketName)"
echo "  queue       $(out QueueUrl)"
echo "  dlq         $(out DlqUrl)"
echo "  sender      $(out Sender)"
echo
DOMAIN_STATUS="$(aws sesv2 get-email-identity --email-identity "${MAIL_DOMAIN}" \
  --query 'DkimAttributes.Status' --output text 2>/dev/null || echo UNKNOWN)"
if [[ "${DOMAIN_STATUS}" != "SUCCESS" ]]; then
  echo "  SES: add these three records in the DNS panel (nic.ua -> ${MAIL_DOMAIN} -> DNS):"
  echo
  printf '    %-6s %-48s %s\n' TYPE "NAME (host)" VALUE
  for i in 1 2 3; do
    printf '    %-6s %-48s %s\n' CNAME "$(relative "$(out "DkimName${i}")")" "$(out "DkimValue${i}")."
  done
  echo
  echo "  Keep the dot at the end of each value: without it nic.ua appends .${MAIL_DOMAIN}."
  echo "  DKIM status: ${DOMAIN_STATUS} - becomes SUCCESS minutes after the records resolve."
else
  log "SES domain ${MAIL_DOMAIN}: DKIM verified"
fi
FIRST="$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" \
  --query "Stacks[0].Parameters[?ParameterKey=='ReportRecipients'].ParameterValue" --output text)"
FIRST="${FIRST%%,*}"
RECIPIENT_OK="$(aws sesv2 get-email-identity --email-identity "${FIRST}" \
  --query VerifiedForSendingStatus --output text 2>/dev/null || echo false)"
if [[ "${RECIPIENT_OK}" != "True" && "${RECIPIENT_OK}" != "true" ]]; then
  echo "  SES sandbox: open the email AWS sent to ${FIRST} and click the link."
else
  log "recipient ${FIRST} verified"
fi
echo
echo "Then: make report-now WEEK=<last week>   and   make report-logs"
