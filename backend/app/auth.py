"""Who is calling: verify the Cognito access token on every /api request.

The frontend's "signed in" state is only a convenience; this is the boundary.
Checked here: the RS256 signature against the user pool's public keys (JWKS),
expiry, issuer, token_use == "access" and the app client id.
"""

import json
import time
import urllib.request
from typing import Annotated, Any

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.concurrency import run_in_threadpool
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.config import Settings, get_settings

# Without a user pool (docker compose before `make deploy-auth`, and the tests)
# everything belongs to this one local user. Production refuses instead.
DEV_USER = "local-dev"
JWKS_TTL_SECONDS = 3600

_bearer = HTTPBearer(auto_error=False)
_keys: dict[str, jwt.PyJWK] = {}
_keys_loaded_at = 0.0


def reset_key_cache() -> None:
    global _keys_loaded_at
    _keys.clear()
    _keys_loaded_at = 0.0


def _load_keys(settings: Settings) -> None:
    """Keys come from COGNITO_JWKS (Lambda: no internet route) or the issuer."""
    global _keys_loaded_at
    if settings.cognito_jwks:
        document = json.loads(settings.cognito_jwks)
    else:
        url = f"{settings.cognito_issuer}/.well-known/jwks.json"
        with urllib.request.urlopen(url, timeout=5) as response:  # noqa: S310 - fixed https URL
            document = json.load(response)
    _keys.clear()
    for jwk in jwt.PyJWKSet.from_dict(document).keys:
        _keys[jwk.key_id] = jwk
    _keys_loaded_at = time.monotonic()


def _signing_key(settings: Settings, kid: str) -> jwt.PyJWK:
    # Cached; refreshed hourly, or once when an unknown key id shows up (rotation).
    stale = time.monotonic() - _keys_loaded_at > JWKS_TTL_SECONDS
    if stale or kid not in _keys:
        _load_keys(settings)
    try:
        return _keys[kid]
    except KeyError:
        raise jwt.InvalidTokenError("unknown signing key") from None


def verify_access_token(token: str, settings: Settings) -> dict[str, Any]:
    kid = jwt.get_unverified_header(token).get("kid", "")
    claims = jwt.decode(
        token,
        key=_signing_key(settings, kid).key,
        algorithms=["RS256"],
        issuer=settings.cognito_issuer,
        options={"require": ["exp", "iss", "sub", "token_use", "client_id"]},
        leeway=30,
    )
    if claims["token_use"] != "access":
        raise jwt.InvalidTokenError("not an access token")
    if claims["client_id"] != settings.cognito_client_id:
        raise jwt.InvalidTokenError("token was issued to another app client")
    return claims


def _unauthorized(detail: str) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=detail,
        headers={"WWW-Authenticate": "Bearer"},
    )


async def current_user(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> str:
    """The caller's Cognito sub."""
    settings = get_settings()
    if not settings.auth_configured:
        if settings.app_env == "production":
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="sign-in is not configured",
            )
        return DEV_USER
    if credentials is None:
        raise _unauthorized("Not signed in")
    try:
        claims = await run_in_threadpool(verify_access_token, credentials.credentials, settings)
    except (jwt.PyJWTError, ValueError, OSError) as exc:
        raise _unauthorized("Invalid or expired token") from exc
    return claims["sub"]


CurrentUser = Annotated[str, Depends(current_user)]
