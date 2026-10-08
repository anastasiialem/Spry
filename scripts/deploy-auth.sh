#!/usr/bin/env bash
# Create/update the Cognito user pool (infra/auth.yaml): managed login with
# email + password and Google. Needs, in .env (gitignored):
#
#   COGNITO_DOMAIN_PREFIX=spry-anastasiia
#   GOOGLE_CLIENT_ID=....apps.googleusercontent.com
#   GOOGLE_CLIENT_SECRET=...
#
# The Google secret goes to CloudFormation as a NoEcho parameter through a
# 0600 file - never on the command line, never into the repo or the bundle.
# The frontend build reads the stack's outputs itself (deploy-frontend.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="${ROOT}/infra/auth.yaml"

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
STACK_NAME="${AUTH_STACK_NAME:-${PROJECT_NAME}-auth}"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
export AWS_DEFAULT_REGION="${AWS_REGION}"

PREFIX="${COGNITO_DOMAIN_PREFIX:-}"
[[ -n "${PREFIX}" ]] || die "set COGNITO_DOMAIN_PREFIX in .env (e.g. spry-anastasiia)"
[[ -n "${GOOGLE_CLIENT_ID:-}" && -n "${GOOGLE_CLIENT_SECRET:-}" ]] \
  || die "set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET in .env (Google Cloud -> Clients)"

# Exact URLs, trailing slash included: the frontend sends
#   redirect_uri = <origin>/auth/callback/    and    logout_uri = <origin>/
ORIGINS=()
[[ -n "${APP_DOMAIN_NAME:-}" ]] && ORIGINS+=("https://${APP_DOMAIN_NAME}")
SITE_CF="$(aws cloudformation describe-stacks --stack-name "${PROJECT_NAME}-frontend" \
  --query "Stacks[0].Outputs[?OutputKey=='DistributionDomainName'].OutputValue" \
  --output text 2>/dev/null || true)"
[[ -n "${SITE_CF}" && "${SITE_CF}" != "None" ]] && ORIGINS+=("https://${SITE_CF}")
ORIGINS+=("http://localhost:${FRONTEND_PORT:-5173}")

CALLBACKS="$(printf '%s/auth/callback/,' "${ORIGINS[@]}")"; CALLBACKS="${CALLBACKS%,}"
LOGOUTS="$(printf '%s/,' "${ORIGINS[@]}")"; LOGOUTS="${LOGOUTS%,}"
log "callback URLs: ${CALLBACKS}"

PARAMS_FILE="$(mktemp)"; chmod 600 "${PARAMS_FILE}"
trap 'rm -f "${PARAMS_FILE}"' EXIT
PROJECT_NAME="${PROJECT_NAME}" PREFIX="${PREFIX}" \
GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID}" GOOGLE_CLIENT_SECRET="${GOOGLE_CLIENT_SECRET}" \
CALLBACKS="${CALLBACKS}" LOGOUTS="${LOGOUTS}" \
python3 - "${PARAMS_FILE}" <<'PY'
import json, os, sys
e = os.environ
params = {
    "ProjectName": e["PROJECT_NAME"],
    "DomainPrefix": e["PREFIX"],
    "GoogleClientId": e["GOOGLE_CLIENT_ID"],
    "GoogleClientSecret": e["GOOGLE_CLIENT_SECRET"],
    "CallbackUrls": e["CALLBACKS"],
    "LogoutUrls": e["LOGOUTS"],
}
json.dump([{"ParameterKey": k, "ParameterValue": v} for k, v in params.items()],
          open(sys.argv[1], "w"))
PY

log "deploying ${STACK_NAME}"
if ! aws cloudformation deploy \
  --stack-name "${STACK_NAME}" \
  --template-file "${TEMPLATE}" \
  --parameter-overrides "file://${PARAMS_FILE}" \
  --no-fail-on-empty-changeset \
  --tags "PROJECT_NAME=${PROJECT_NAME}"; then
  warn "deploy failed - most recent failure reasons:"
  aws cloudformation describe-stack-events --stack-name "${STACK_NAME}" --max-items 30 \
    --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`||ResourceStatus==`UPDATE_FAILED`].[LogicalResourceId,ResourceStatusReason]' \
    --output table >&2 || true
  exit 1
fi

out() {
  aws cloudformation describe-stacks --stack-name "${STACK_NAME}" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}
# Public values only (no secret) - for docker compose; the deployed build
# reads the stack outputs itself.
env_set() {
  KEY="$1" VALUE="$2" ENV_FILE="${ROOT}/.env" python3 - <<'PY'
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
}
env_set COGNITO_AUTHORITY "$(out Authority)"
env_set COGNITO_CLIENT_ID "$(out ClientId)"
env_set COGNITO_DOMAIN "$(out Domain)"

echo
echo "  user pool   $(out UserPoolId)"
echo "  client id   $(out ClientId)"
echo "  authority   $(out Authority)"
echo "  login host  $(out Domain)"
echo
echo "  Google OAuth client must have:"
echo "    Authorised JavaScript origin  $(out Domain)"
echo "    Authorised redirect URI       $(out GoogleRedirectUri)"
echo
echo "Next: make deploy-frontend (it reads these outputs itself)."
