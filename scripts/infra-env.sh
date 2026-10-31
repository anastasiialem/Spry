#!/usr/bin/env bash
# After HCP Terraform has applied infra/: copy the public outputs into .env (for
# docker compose) and print what is still done by hand - the Google OAuth
# client's URIs, the three DKIM CNAMEs, the SES sandbox confirmation.
#
# Reads `terraform output`, so it needs `terraform login` once and
# `make infra-init`. Never applies anything.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { printf '\033[36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

if [[ -f "${ROOT}/.env" ]]; then
  preset="$(export -p)"; set -a
  # shellcheck disable=SC1091
  source "${ROOT}/.env"; set +a; eval "${preset}"
fi
for var in AWS_PROFILE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN; do
  [[ -n "${!var:-}" ]] || unset "${var}"
done
export AWS_DEFAULT_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"

tf_out() { terraform -chdir="${ROOT}/infra" output -raw "$1"; }
tf_out user_pool_id >/dev/null 2>&1 \
  || die "no terraform outputs - run terraform login, then make infra-init"

# The same .env writer as before: replace the line or append it.
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

# Public values only. The Google secret lives in the HCP Terraform workspace.
env_set COGNITO_AUTHORITY "$(tf_out authority)"
env_set COGNITO_CLIENT_ID "$(tf_out client_id)"
env_set COGNITO_DOMAIN "$(tf_out domain)"
env_set PARSER_URL "$(tf_out parser_url)"
log "wrote COGNITO_AUTHORITY, COGNITO_CLIENT_ID, COGNITO_DOMAIN, PARSER_URL to .env"

echo
echo "  user pool   $(tf_out user_pool_id)"
echo "  client id   $(tf_out client_id)"
echo "  login host  $(tf_out domain)"
echo "  parser url  $(tf_out parser_url)  (model $(tf_out parser_model))"
echo "  bucket      $(tf_out reports_bucket)"
echo "  sender      $(tf_out report_sender)"
echo
echo "  Google OAuth client must have:"
echo "    Authorised JavaScript origin  $(tf_out domain)"
echo "    Authorised redirect URI       $(tf_out google_redirect_uri)"
echo

# --- SES: DKIM and the sandbox -------------------------------------------------

MAIL_DOMAIN="$(tf_out report_sender)"; MAIL_DOMAIN="${MAIL_DOMAIN#*@}"
DKIM_STATUS="$(aws sesv2 get-email-identity --email-identity "${MAIL_DOMAIN}" \
  --query 'DkimAttributes.Status' --output text 2>/dev/null || echo UNKNOWN)"
if [[ "${DKIM_STATUS}" != "SUCCESS" ]]; then
  echo "  SES: add these three CNAMEs in the DNS panel (keep the trailing dot):"
  terraform -chdir="${ROOT}/infra" output -json dkim_records \
    | python3 -c 'import json,sys; [print(f"    CNAME  {k}  {v}.") for k,v in json.load(sys.stdin).items()]'
  echo "  DKIM status: ${DKIM_STATUS}"
else
  log "SES domain ${MAIL_DOMAIN}: DKIM verified"
fi
