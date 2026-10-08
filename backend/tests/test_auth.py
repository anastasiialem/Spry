"""The API with a user pool configured: tokens, and one user's data per user."""

import json
import time
from collections.abc import Iterator

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from httpx import AsyncClient

from app import auth
from app.config import get_settings

POOL = "us-east-1_TESTPOOL"
CLIENT = "test-client-id"
ISSUER = f"https://cognito-idp.us-east-1.amazonaws.com/{POOL}"
KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
OTHER_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)

MEETING = {
    "title": "Private sync",
    "starts_at": "2026-10-05T09:00:00Z",
    "ends_at": "2026-10-05T10:00:00Z",
    "attendee_count": 2,
}


def _jwks() -> str:
    jwk = json.loads(jwt.algorithms.RSAAlgorithm.to_jwk(KEY.public_key()))
    jwk.update(kid="test-kid", alg="RS256", use="sig")
    return json.dumps({"keys": [jwk]})


def token(sub: str, *, key=KEY, **overrides) -> dict[str, str]:
    claims = {
        "sub": sub,
        "iss": ISSUER,
        "client_id": CLIENT,
        "token_use": "access",
        "exp": int(time.time()) + 600,
    } | overrides
    encoded = jwt.encode(claims, key, algorithm="RS256", headers={"kid": "test-kid"})
    return {"Authorization": f"Bearer {encoded}"}


@pytest.fixture(autouse=True)
def pool(monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    monkeypatch.setenv("COGNITO_USER_POOL_ID", POOL)
    monkeypatch.setenv("COGNITO_CLIENT_ID", CLIENT)
    monkeypatch.setenv("COGNITO_JWKS", _jwks())
    get_settings.cache_clear()
    auth.reset_key_cache()
    yield
    get_settings.cache_clear()
    auth.reset_key_cache()


async def test_health_stays_public(client: AsyncClient) -> None:
    assert (await client.get("/health")).status_code == 200


async def test_no_token_is_401(client: AsyncClient) -> None:
    response = await client.get("/api/meetings")
    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"


@pytest.mark.parametrize(
    "headers",
    [
        token("alice", key=OTHER_KEY),  # signed by someone else
        token("alice", exp=int(time.time()) - 3600),  # expired
        token("alice", iss="https://evil.example"),  # another issuer
        token("alice", client_id="another-app"),  # another app client
        token("alice", token_use="id"),  # an ID token, not an access token
        {"Authorization": "Bearer not-a-jwt"},
    ],
)
async def test_bad_tokens_are_401(client: AsyncClient, headers: dict[str, str]) -> None:
    assert (await client.get("/api/meetings", headers=headers)).status_code == 401


async def test_each_user_sees_only_their_meetings(client: AsyncClient) -> None:
    alice, bob = token("alice"), token("bob")
    created = await client.post("/api/meetings", json=MEETING, headers=alice)
    assert created.status_code == 201
    meeting_id = created.json()["id"]

    assert [m["id"] for m in (await client.get("/api/meetings", headers=alice)).json()] == [
        meeting_id
    ]
    assert (await client.get("/api/meetings", headers=bob)).json() == []

    # Bob cannot touch Alice's meeting or its files - it looks missing.
    url = f"/api/meetings/{meeting_id}"
    assert (await client.patch(url, json={"status": "done"}, headers=bob)).status_code == 404
    assert (await client.get(f"{url}/attachments", headers=bob)).status_code == 404

    upload = await client.post(
        f"{url}/attachments",
        params={"filename": "notes.txt"},
        content=b"secret",
        headers=alice | {"Content-Type": "text/plain"},
    )
    attachment_id = upload.json()["id"]
    assert (await client.get(f"/api/attachments/{attachment_id}", headers=bob)).status_code == 404
    assert (
        await client.delete(f"/api/attachments/{attachment_id}", headers=bob)
    ).status_code == 404
    own = await client.get(f"/api/attachments/{attachment_id}", headers=alice)
    assert own.content == b"secret"


async def test_production_without_pool_refuses(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("COGNITO_USER_POOL_ID", "")
    monkeypatch.setenv("APP_ENV", "production")
    get_settings.cache_clear()
    assert (await client.get("/api/meetings")).status_code == 503
