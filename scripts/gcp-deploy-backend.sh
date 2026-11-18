#!/usr/bin/env bash
# Build the API's runtime image, push it to Artifact Registry and roll Cloud Run.
#
# Terraform (gcp/) owns the service, its database, secret and identity; it
# ignores the image, which this script owns - the same split as Lambda on AWS.
# Credentials: your own gcloud login (gcloud auth login), never a key file.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { printf '\033[36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

command -v gcloud >/dev/null 2>&1 || die "gcloud is required: brew install --cask gcloud-cli"
command -v docker >/dev/null 2>&1 || die "docker is required"

tf_out() { terraform -chdir="${ROOT}/gcp" output -raw "$1" 2>/dev/null || true; }
REPO="$(tf_out image_repository)"
SERVICE="$(tf_out api_service)"
[[ -n "${REPO}" && -n "${SERVICE}" ]] \
  || die "no gcp/ outputs - terraform login, make gcp-init, and apply the spry-gcp workspace first"

# us-central1-docker.pkg.dev/<project>/spry -> project and region
REGISTRY_HOST="${REPO%%/*}"
REGION="${REGISTRY_HOST%-docker.pkg.dev}"
PROJECT="$(cut -d/ -f2 <<<"${REPO}")"

TAG="$(git -C "${ROOT}" rev-parse --short HEAD)$(git -C "${ROOT}" diff --quiet || echo -dirty)"
IMAGE="${REPO}/backend:${TAG}"

log "docker login to ${REGISTRY_HOST} with your gcloud credentials"
gcloud auth configure-docker "${REGISTRY_HOST}" --quiet >/dev/null

# Cloud Run runs linux/amd64; a Mac builds arm64 unless told otherwise.
log "building ${IMAGE} (target runtime, linux/amd64)"
docker build --platform linux/amd64 --target runtime -t "${IMAGE}" "${ROOT}/backend"
docker push "${IMAGE}"

log "rolling ${SERVICE} in ${REGION}"
gcloud run services update "${SERVICE}" \
  --project "${PROJECT}" --region "${REGION}" \
  --image "${IMAGE}" --quiet

URL="$(tf_out api_url)"
echo
echo "  api      ${URL}"
echo "  health   ${URL}/health"
echo "  logs     gcloud run services logs read ${SERVICE} --project ${PROJECT} --region ${REGION}"
echo
