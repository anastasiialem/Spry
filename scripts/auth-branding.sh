#!/usr/bin/env bash
# The sign-in page background (infra/assets/login-background.jpg), set through
# the managed-login branding API on top of the style Terraform creates
# (infra/auth.tf). Run once after the user pool exists; re-running replaces it.
# Terraform ignores the branding's settings and assets, so this survives applies.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m==>\033[0m %s\n' "$*" >&2; }
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

# --- managed login: page background ------------------------------------------
# Terraform creates the default style (and ignores its settings and assets); the background image goes on top
# through the API: read the full current settings, switch the page background
# image on, upload the image. Re-running replaces it.
BG="${ROOT}/infra/assets/login-background.jpg"
if [[ -f "${BG}" ]]; then
  log "setting the sign-in page background (${BG#"${ROOT}"/})"
  POOL_ID="$(tf_out user_pool_id)" CLIENT_ID="$(tf_out client_id)" BRANDING_ID="$(tf_out managed_login_branding_id)" \
  BG="${BG}" python3 - <<'PY' || warn "could not set the background - the sign-in page still works"
import base64, json, os, subprocess, tempfile

def aws(*args):
    return json.loads(subprocess.check_output(["aws", "cognito-idp", *args, "--output", "json"]))

current = aws("describe-managed-login-branding",
              "--user-pool-id", os.environ["POOL_ID"],
              "--managed-login-branding-id", os.environ["BRANDING_ID"],
              "--return-merged-resources")["ManagedLoginBranding"]
settings = current.get("Settings") or {}
page = settings.setdefault("components", {}).setdefault("pageBackground", {})
page.setdefault("image", {})["enabled"] = True

# One copy per colour mode: the default style ships its own LIGHT and DARK
# page backgrounds, and a DYNAMIC asset does not replace them.
data = base64.b64encode(open(os.environ["BG"], "rb").read()).decode()
assets = [
    {"Category": "PAGE_BACKGROUND", "ColorMode": mode, "Extension": "JPEG", "Bytes": data}
    for mode in ("LIGHT", "DARK")
]
# Only our own assets: the merged defaults include button icons for providers
# this pool does not have (Apple, Facebook, Amazon), which the API rejects.
request = {
    "UserPoolId": os.environ["POOL_ID"],
    "ManagedLoginBrandingId": os.environ["BRANDING_ID"],
    "UseCognitoProvidedValues": False,
    "Settings": settings,
    "Assets": assets,
}
with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as fh:
    json.dump(request, fh)
try:
    subprocess.check_call(["aws", "cognito-idp", "update-managed-login-branding",
                           "--cli-input-json", f"file://{fh.name}"], stdout=subprocess.DEVNULL)
finally:
    os.unlink(fh.name)

after = aws("describe-managed-login-branding",
            "--user-pool-id", os.environ["POOL_ID"],
            "--managed-login-branding-id", os.environ["BRANDING_ID"])["ManagedLoginBranding"]
bgs = [f"{a['ColorMode']}" for a in after.get("Assets") or [] if a["Category"] == "PAGE_BACKGROUND"]
print("    page background set for:", ", ".join(bgs) or "nothing (!)")
PY
fi

