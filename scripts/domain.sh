#!/usr/bin/env bash
# Custom domain + HTTPS for both services, with DNS hosted anywhere (nic.ua here).
#
#   make domain-cert DOMAIN=spry.pp.ua   1. request one ACM certificate for app.<d> and api.<d>,
#                                           print the validation CNAMEs, wait until it is issued,
#                                           write the domain settings into .env
#   make deploy-backend                  2. api.<d> distribution in front of the Lambda
#   make deploy-frontend                 3. app.<d> alias on the site's distribution
#   make domain-dns                      4. print the two routing CNAMEs and check them
#
# The same record type shows up twice, for different reasons:
#   - validation: _<hash>.app.<d> CNAME _<hash>.acm-validations.aws  -> proves you control <d>
#   - routing:    app.<d>        CNAME dxxxx.cloudfront.net          -> sends visitors there
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT}/.env"

log() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m==>\033[0m %s\n' "$*" >&2; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

if [[ -f "${ENV_FILE}" ]]; then
  preset="$(export -p)"
  set -a
  # shellcheck disable=SC1091
  source "${ENV_FILE}"
  set +a
  eval "${preset}"
fi
for var in AWS_PROFILE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN; do
  [[ -n "${!var:-}" ]] || unset "${var}"
done

PROJECT_NAME="${PROJECT_NAME:-spry}"
# CloudFront only takes certificates from us-east-1, whatever region the rest is in.
ACM_REGION=us-east-1

env_set() {
  KEY="$1" VALUE="$2" ENV_FILE="${ENV_FILE}" python3 - <<'PY'
import os, re
key, value, path = os.environ["KEY"], os.environ["VALUE"], os.environ["ENV_FILE"]
lines = open(path).read().splitlines() if os.path.exists(path) else []
pattern = re.compile(rf"^{re.escape(key)}=")
for i, line in enumerate(lines):
    if pattern.match(line):
        lines[i] = f"{key}={value}"
        break
else:
    lines.append(f"{key}={value}")
open(path, "w").write("\n".join(lines) + "\n")
PY
  log "wrote ${1}=${2} to .env"
}

# "_abc.app.spry.pp.ua." -> "_abc.app" : most registrar panels want the host
# relative to the zone, without the trailing dot.
relative() {
  local name="${1%.}"
  printf '%s' "${name%."${DOMAIN}"}"
}

stack_output() {
  aws cloudformation describe-stacks --stack-name "$1" \
    --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue" --output text 2>/dev/null || true
}

cmd_cert() {
  DOMAIN="${DOMAIN:-${DOMAIN_NAME:-}}"
  [[ -n "${DOMAIN}" ]] || die "usage: make domain-cert DOMAIN=example.com"
  DOMAIN="${DOMAIN%.}"
  local app="app.${DOMAIN}" api="api.${DOMAIN}"

  # Reuse a certificate that already covers both names (re-running is safe).
  local arn
  arn="$(aws acm list-certificates --region "${ACM_REGION}" \
    --certificate-statuses PENDING_VALIDATION ISSUED \
    --query "CertificateSummaryList[?DomainName=='${app}'].CertificateArn | [0]" \
    --output text)"
  if [[ -z "${arn}" || "${arn}" == "None" ]]; then
    log "requesting a certificate for ${app} and ${api} in ${ACM_REGION}"
    arn="$(aws acm request-certificate --region "${ACM_REGION}" \
      --domain-name "${app}" \
      --subject-alternative-names "${api}" \
      --validation-method DNS \
      --tags "Key=PROJECT_NAME,Value=${PROJECT_NAME}" \
      --query CertificateArn --output text)"
  else
    log "reusing certificate ${arn}"
  fi

  # The validation records appear a few seconds after the request.
  local records=""
  for _ in $(seq 1 20); do
    records="$(aws acm describe-certificate --region "${ACM_REGION}" --certificate-arn "${arn}" \
      --query 'Certificate.DomainValidationOptions[].ResourceRecord.[Name,Value]' \
      --output text 2>/dev/null || true)"
    [[ -n "${records}" && "${records}" != "None" ]] && break
    sleep 3
  done
  [[ -n "${records}" ]] || die "ACM did not return validation records yet - run this again"

  echo
  echo "  Add these records in your DNS panel (nic.ua: My domains -> ${DOMAIN} -> DNS):"
  echo
  printf '    %-6s %-48s %s\n' TYPE "NAME (host)" VALUE
  sort -u <<<"${records}" | while read -r name value; do
    printf '    %-6s %-48s %s\n' CNAME "$(relative "${name}")" "${value%.}"
  done
  echo
  echo "  They prove to AWS that you control ${DOMAIN}. Leave them in place:"
  echo "  ACM re-checks them to renew the certificate every year."
  echo

  env_set DOMAIN_NAME "${DOMAIN}"
  env_set APP_DOMAIN_NAME "${app}"
  env_set API_DOMAIN_NAME "${api}"
  env_set APP_CERTIFICATE_ARN "${arn}"
  env_set API_CERTIFICATE_ARN "${arn}"

  # The site must be allowed to call the API from its new origin; keep the
  # cloudfront.net one working too.
  local site
  site="$(stack_output "${PROJECT_NAME}-frontend" DistributionDomainName)"
  local origins="https://${app}"
  [[ -n "${site}" && "${site}" != "None" ]] && origins="${origins},https://${site}"
  env_set API_CORS_ORIGINS "${origins}"

  local status
  status="$(aws acm describe-certificate --region "${ACM_REGION}" --certificate-arn "${arn}" \
    --query Certificate.Status --output text)"
  if [[ "${status}" != "ISSUED" ]]; then
    log "waiting for validation (usually 5-30 minutes after the records are added; Ctrl+C is safe - re-run later)"
    aws acm wait certificate-validated --region "${ACM_REGION}" --certificate-arn "${arn}" \
      || die "not validated yet - check the records above, then run this again"
  fi
  log "certificate ISSUED"
  echo
  echo "Next: make deploy-backend && make deploy-frontend && make domain-dns"
}

cmd_dns() {
  DOMAIN="${DOMAIN:-${DOMAIN_NAME:-}}"
  [[ -n "${DOMAIN}" ]] || die "run make domain-cert DOMAIN=... first"
  local app="app.${DOMAIN}" api="api.${DOMAIN}"
  local site_cf api_cf
  site_cf="$(stack_output "${PROJECT_NAME}-frontend" DistributionDomainName)"
  api_cf="$(stack_output "${PROJECT_NAME}-backend" ApiDistributionDomainName)"
  [[ -n "${site_cf}" && "${site_cf}" != "None" ]] || die "no frontend stack - make deploy-frontend"
  [[ -n "${api_cf}" && "${api_cf}" != "none" && "${api_cf}" != "None" ]] \
    || die "no api distribution yet - make deploy-backend (after domain-cert)"

  echo
  echo "  Routing records - add these in your DNS panel too:"
  echo
  printf '    %-6s %-10s %s\n' TYPE NAME VALUE
  printf '    %-6s %-10s %s\n' CNAME app "${site_cf}"
  printf '    %-6s %-10s %s\n' CNAME api "${api_cf}"
  echo

  if command -v dig >/dev/null 2>&1; then
    for host in "${app}" "${api}"; do
      local got
      got="$(dig +short CNAME "${host}" | head -1)"
      if [[ -n "${got}" ]]; then
        log "${host} -> ${got%.}"
      else
        warn "${host} does not resolve yet (DNS changes take minutes, sometimes hours)"
      fi
    done
    echo
  fi
  echo "  Then:  curl https://${api}/health   and open   https://${app}"
}

case "${1:-}" in
  cert) cmd_cert ;;
  dns) cmd_dns ;;
  *) die "usage: $0 cert|dns" ;;
esac
