#!/usr/bin/env bash
# Build the Vite bundle and put it behind CloudFront (private S3 bucket).
#
# The API URL is compiled into the bundle - VITE_* is substituted at build
# time, not read at runtime - so this builds against BACKEND_URL from .env,
# which scripts/deploy-backend.sh writes. Deploy the backend first.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="${ROOT}/infra/frontend.yaml"
APP="${ROOT}/frontend"

log() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m==>\033[0m %s\n' "$*" >&2; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

if [[ -f "${ROOT}/.env" ]]; then
  # Variables already exported win over .env: `AWS_REGION=eu-central-1 make x`
  # must not be quietly reset to the region .env names.
  preset="$(export -p)"
  set -a
  # shellcheck disable=SC1091
  source "${ROOT}/.env"
  set +a
  eval "${preset}"
fi

# A blank AWS_PROFILE is read as a profile literally named "", and blank keys
# short-circuit the credential chain. Treat empty as absent.
for var in AWS_PROFILE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN; do
  [[ -n "${!var:-}" ]] || unset "${var}"
done

PROJECT_NAME="${PROJECT_NAME:-spry}"
STACK_NAME="${FRONTEND_STACK_NAME:-${PROJECT_NAME}-frontend}"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
export AWS_DEFAULT_REGION="${AWS_REGION}"

# --- preflight --------------------------------------------------------------

command -v aws >/dev/null 2>&1 || die "aws cli is required but not installed"
aws sts get-caller-identity >/dev/null 2>&1 \
  || die "no usable AWS credentials - run aws configure (or set AWS_PROFILE)"

# --- which API does this build talk to? -------------------------------------

# VITE_API_URL in .env points at localhost for Compose; a deployed bundle is
# compiled against BACKEND_URL instead.
API_URL="${BACKEND_URL:-}"
API_URL="${API_URL%/}"
[[ -n "${API_URL}" ]] || die "BACKEND_URL is not set in .env - run make deploy-backend first"
# An HTTPS page may not call an HTTP API; plain HTTP here means a hand-edited .env.
[[ "${API_URL}" == https://* ]] || die "BACKEND_URL must be https://"

# --- infrastructure ---------------------------------------------------------

if ! aws cloudformation describe-stacks --stack-name "${STACK_NAME}" >/dev/null 2>&1; then
  log "first deploy - creating ${STACK_NAME} (CloudFront takes a few minutes)"
else
  log "updating ${STACK_NAME}"
fi

# Empty values are left out, so CloudFormation keeps what the stack already has
# (CI has no .env, and must not drop the custom domain).
PARAMS=("ProjectName=${PROJECT_NAME}")
[[ -n "${APP_DOMAIN_NAME:-}" ]] && PARAMS+=("DomainName=${APP_DOMAIN_NAME}")
[[ -n "${APP_CERTIFICATE_ARN:-}" ]] && PARAMS+=("AcmCertificateArn=${APP_CERTIFICATE_ARN}")
[[ -n "${HOSTED_ZONE_ID:-}" ]] && PARAMS+=("HostedZoneId=${HOSTED_ZONE_ID}")

if ! aws cloudformation deploy \
  --stack-name "${STACK_NAME}" \
  --template-file "${TEMPLATE}" \
  --parameter-overrides "${PARAMS[@]}" \
  --no-fail-on-empty-changeset \
  --tags "PROJECT_NAME=${PROJECT_NAME}"; then
  warn "deploy failed - most recent failure reasons:"
  aws cloudformation describe-stack-events --stack-name "${STACK_NAME}" \
    --max-items 40 \
    --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`||ResourceStatus==`UPDATE_FAILED`].[LogicalResourceId,ResourceStatusReason]' \
    --output table >&2 || true
  exit 1
fi

outputs() {
  aws cloudformation describe-stacks --stack-name "${STACK_NAME}" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

BUCKET="$(outputs BucketName)"
DISTRIBUTION_ID="$(outputs DistributionId)"
SITE_URL="$(outputs SiteUrl)"

# --- build ------------------------------------------------------------------

log "building against ${API_URL}"
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
rm -rf "${APP}/dist"
if command -v pnpm >/dev/null 2>&1 || command -v corepack >/dev/null 2>&1; then
  # A local Node toolchain (CI, or a laptop that has one).
  PM=(pnpm); command -v pnpm >/dev/null 2>&1 || PM=(corepack pnpm)
  (cd "${APP}" && "${PM[@]}" install --frozen-lockfile && VITE_API_URL="${API_URL}" "${PM[@]}" build)
else
  # No Node here: build in the same node image Compose uses. node_modules
  # goes into a named volume so Linux binaries never land in the host folder.
  command -v docker >/dev/null 2>&1 || die "need either pnpm/corepack or docker to build"
  log "no local Node - building inside node:22-alpine"
  docker run --rm \
    -v "${APP}:/app" \
    -v "${PROJECT_NAME}_build_node_modules:/app/node_modules" \
    -v "${PROJECT_NAME}_pnpm_store:/pnpm-store" \
    -e npm_config_store_dir=/pnpm-store \
    -e CI=true \
    -w /app \
    -e COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
    -e VITE_API_URL="${API_URL}" \
    node:22-alpine \
    sh -c "corepack enable && pnpm install --frozen-lockfile && pnpm build"
fi
[[ -f "${APP}/dist/index.html" ]] || die "the build produced no dist/index.html"

# --- upload -----------------------------------------------------------------

# Hashed assets first and without --delete: a browser still on the previous
# build may ask for its chunks. They never change, so they cache for a year.
log "uploading to s3://${BUCKET}"
aws s3 sync "${APP}/dist/assets" "s3://${BUCKET}/assets" \
  --cache-control "public,max-age=31536000,immutable" \
  --only-show-errors

# Everything else (index.html, images) must revalidate, or a deploy would not
# be visible until a TTL ran out.
aws s3 sync "${APP}/dist" "s3://${BUCKET}" \
  --delete \
  --exclude "assets/*" \
  --cache-control "public,max-age=0,must-revalidate" \
  --only-show-errors

log "invalidating the CloudFront cache"
INVALIDATION_ID="$(aws cloudfront create-invalidation \
  --distribution-id "${DISTRIBUTION_ID}" \
  --paths "/*" \
  --query Invalidation.Id --output text)"
aws cloudfront wait invalidation-completed \
  --distribution-id "${DISTRIBUTION_ID}" \
  --id "${INVALIDATION_ID}" 2>/dev/null || true

# --- report -----------------------------------------------------------------

echo
echo "  site       ${SITE_URL}"
echo "  api        ${API_URL}"
echo "  bucket     s3://${BUCKET}"
echo
echo "Allow the site's origin through CORS: put"
echo "  API_CORS_ORIGINS=${SITE_URL}"
echo "in .env and run make deploy-backend again."
echo
