#!/usr/bin/env bash
# Build the Vite bundle for Google Cloud and deploy it to Firebase Hosting.
#
# One origin: Firebase rewrites /api/** to the Cloud Run service
# (gcp/firebase.json), so the bundle calls relative /api/... URLs - no CORS,
# as CloudFront did on AWS. Sign-in and the agenda parser are still on AWS:
# their settings come from infra/'s Terraform outputs, like deploy-frontend.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${ROOT}/frontend"

log() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m==>\033[0m %s\n' "$*" >&2; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

gcp_out() { terraform -chdir="${ROOT}/gcp" output -raw "$1" 2>/dev/null || true; }
aws_out() { terraform -chdir="${ROOT}/infra" output -raw "$1" 2>/dev/null || true; }

SITE_URL="$(gcp_out site_url)"
[[ -n "${SITE_URL}" ]] || die "no gcp/ outputs - make gcp-init and apply the spry-gcp workspace first"
PROJECT="${SITE_URL#https://}"; PROJECT="${PROJECT%.web.app}"

export VITE_COGNITO_AUTHORITY="$(aws_out authority)"
export VITE_COGNITO_CLIENT_ID="$(aws_out client_id)"
export VITE_COGNITO_DOMAIN="$(aws_out domain)"
[[ -n "${VITE_COGNITO_CLIENT_ID}" ]] \
  || warn "no infra/ outputs (terraform login, make infra-init) - building without sign-in"
PARSER_URL="$(aws_out parser_url)"
export VITE_PARSER_URL="${PARSER_URL%/}"
# Empty, not unset: relative /api/... on the site's own origin.
export VITE_API_URL=""

log "building for ${SITE_URL} (API through the /api/** rewrite)"
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
rm -rf "${APP}/dist"
# pnpm, else corepack, else npx with the version package.json pins (Node 25+
# no longer ships corepack).
PNPM_VERSION="$(sed -n 's/.*"packageManager": *"pnpm@\([^"]*\)".*/\1/p' "${APP}/package.json")"
if command -v pnpm >/dev/null 2>&1; then PM=(pnpm)
elif command -v corepack >/dev/null 2>&1; then PM=(corepack pnpm)
else PM=(npx --yes "pnpm@${PNPM_VERSION}"); fi
(cd "${APP}" && "${PM[@]}" install --frozen-lockfile && "${PM[@]}" build)
[[ -f "${APP}/dist/index.html" ]] || die "the build produced no dist/index.html"

FIREBASE=(firebase); command -v firebase >/dev/null 2>&1 || FIREBASE=(npx --yes firebase-tools@14)
# Firebase only serves a folder inside the one holding firebase.json.
rsync -a --delete "${APP}/dist/" "${ROOT}/gcp/public/"
log "deploying to Firebase Hosting (project ${PROJECT})"
(cd "${ROOT}/gcp" && "${FIREBASE[@]}" deploy --only hosting --project "${PROJECT}")

echo
echo "  site   ${SITE_URL}"
echo "  api    ${SITE_URL}/api/meetings  (rewritten to Cloud Run)"
echo
