#!/usr/bin/env bash
# Deploy "Paste an agenda" (infra/ai.yml): the agenda-parser Lambda behind its
# own function URL, outside the VPC, calling a model on Bedrock (Mistral Large 3); and a monthly
# budget alarm.
#
# The image is the one the API runs (make deploy-backend first); the Cognito
# ids come from the auth stack. Optional in .env:
#
#   PARSER_MODEL=mistral.ministral-3-14b-instruct   default mistral.mistral-large-3-675b-instruct
#   BUDGET_EMAIL=you@example.com              defaults to the first REPORT_RECIPIENTS
#   BUDGET_LIMIT_USD=5
#
# Writes PARSER_URL to .env; make deploy-frontend compiles it into the bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="${ROOT}/infra/ai.yml"

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
STACK_NAME="${AI_STACK_NAME:-${PROJECT_NAME}-ai}"
BACKEND_STACK="${STACK_NAME_BACKEND:-${PROJECT_NAME}-backend}"
AUTH_STACK="${AUTH_STACK_NAME:-${PROJECT_NAME}-auth}"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
export AWS_DEFAULT_REGION="${AWS_REGION}"

aws sts get-caller-identity >/dev/null 2>&1 || die "no usable AWS credentials"

stack_value() { # stack, Outputs|Parameters, key
  local field=OutputKey value=OutputValue
  [[ "$2" == Parameters ]] && field=ParameterKey value=ParameterValue
  aws cloudformation describe-stacks --stack-name "$1" \
    --query "Stacks[0].$2[?${field}=='$3'].${value}" --output text
}

aws cloudformation describe-stacks --stack-name "${BACKEND_STACK}" >/dev/null 2>&1 \
  || die "no ${BACKEND_STACK} stack - run make deploy-backend first"
aws cloudformation describe-stacks --stack-name "${AUTH_STACK}" >/dev/null 2>&1 \
  || die "no ${AUTH_STACK} stack - run make deploy-auth first (every parse needs a signed-in user)"

ARCHITECTURE="$(stack_value "${BACKEND_STACK}" Parameters Architecture)"
# The image the API runs right now (CI may have rolled it since the stack's
# parameter was last set).
IMAGE_URI="$(aws lambda get-function --function-name "$(stack_value "${BACKEND_STACK}" Outputs FunctionName)" \
  --query Code.ImageUri --output text)"
POOL_ID="$(stack_value "${AUTH_STACK}" Outputs UserPoolId)"
CLIENT_ID="$(stack_value "${AUTH_STACK}" Outputs ClientId)"
# The site's origins (what the API allows), plus Vite's dev server.
ORIGINS="${API_CORS_ORIGINS:-}"
[[ -n "${ORIGINS}" ]] || die "set API_CORS_ORIGINS in .env (the site's origins, as for the API)"
[[ ",${ORIGINS}," == *",http://localhost:5173,"* ]] || ORIGINS="${ORIGINS},http://localhost:5173"
BUDGET_EMAIL="${BUDGET_EMAIL:-${REPORT_RECIPIENTS%%,*}}"
log "image ${IMAGE_URI}"
log "origins ${ORIGINS}"
[[ -n "${BUDGET_EMAIL}" ]] && log "budget alarm -> ${BUDGET_EMAIL}" \
  || warn "no BUDGET_EMAIL (or REPORT_RECIPIENTS) - deploying without the budget alarm"

PARAMS=(
  "ProjectName=${PROJECT_NAME}"
  "ImageUri=${IMAGE_URI}"
  "Architecture=${ARCHITECTURE}"
  "CognitoUserPoolId=${POOL_ID}"
  "CognitoClientId=${CLIENT_ID}"
  "AllowedOrigins=${ORIGINS}"
  "BudgetEmail=${BUDGET_EMAIL}"
)
# Not given: the stack keeps its current model (first deploy: the template's).
[[ -n "${PARSER_MODEL:-}" ]] && PARAMS+=("ParserModel=${PARSER_MODEL}")
[[ -n "${BUDGET_LIMIT_USD:-}" ]] && PARAMS+=("BudgetLimitUsd=${BUDGET_LIMIT_USD}")

log "deploying ${STACK_NAME}"
if ! aws cloudformation deploy \
  --stack-name "${STACK_NAME}" \
  --template-file "${TEMPLATE}" \
  --parameter-overrides "${PARAMS[@]}" \
  --capabilities CAPABILITY_IAM \
  --no-fail-on-empty-changeset \
  --tags "PROJECT_NAME=${PROJECT_NAME}"; then
  warn "deploy failed - most recent failure reasons:"
  aws cloudformation describe-stack-events --stack-name "${STACK_NAME}" --max-items 30 \
    --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`||ResourceStatus==`UPDATE_FAILED`].[LogicalResourceId,ResourceStatusReason]' \
    --output table >&2 || true
  exit 1
fi

PARSER_URL="$(stack_value "${STACK_NAME}" Outputs ParserUrl)"
PARSER_URL="${PARSER_URL%/}"

# The same .env writer as deploy-auth.sh: replace the line or append it.
KEY=PARSER_URL VALUE="${PARSER_URL}" ENV_FILE="${ROOT}/.env" python3 - <<'PY'
import os, re
k, v, path = os.environ["KEY"], os.environ["VALUE"], os.environ["ENV_FILE"]
lines = open(path).read().splitlines() if os.path.exists(path) else []
for i, line in enumerate(lines):
    if re.match(rf"^{re.escape(k)}=", line):
        lines[i] = f"{k}={v}"
        break
else:
    lines.append(f"{k}={v}")
open(path, "w").write("\n".join(lines) + "\n")
PY

echo
echo "  parser url  ${PARSER_URL}"
echo "  model       $(stack_value "${STACK_NAME}" Outputs ParserModel)"
echo "  logs        make ai-logs"
echo
echo "Next: make deploy-frontend (it reads the parser URL itself)."
if [[ -n "${BUDGET_EMAIL}" ]]; then
  echo "AWS Budgets emails ${BUDGET_EMAIL} when the month passes \$${BUDGET_LIMIT_USD:-5}."
fi
