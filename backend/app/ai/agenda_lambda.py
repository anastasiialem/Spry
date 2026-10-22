"""Entry point of the agenda-parser Lambda (infra/ai.yml), behind its own function URL.

The backend's image with another command, outside the VPC: it needs Bedrock and
Cognito's public keys, never the database. It only answers with a suggestion;
saving goes through the main API (PUT /api/meetings/{id}/agenda).

    POST {"text": "...", "today": "2026-10-19", "tz": "Europe/Kyiv"}
    Authorization: Bearer <Cognito access token>

    200 {"agenda": ParsedAgenda, "model": "...", "prompt_version": "..."}
    400 bad body   401 no/bad token   413 text too long   422 no agenda found
    429 Bedrock is throttling   503 Bedrock unavailable

CORS (and the OPTIONS preflight) is the function URL's job, not this code's.
"""

import base64
import json
import logging
import time
from datetime import date
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import jwt

from app.ai.agenda import (
    MAX_TEXT_CHARS,
    PROMPT_VERSION,
    AgendaParseError,
    cost_usd,
    parse_agenda,
)
from app.auth import verify_access_token
from app.config import get_settings

log = logging.getLogger("spry.agenda_parser")
# Lambda's runtime puts a handler on the root logger; this lets INFO through.
log.setLevel(logging.INFO)


def _answer(status: int, body: dict[str, Any]) -> dict[str, Any]:
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body, ensure_ascii=False),
    }


def _error(status: int, message: str) -> dict[str, Any]:
    return _answer(status, {"error": message})


def _caller(headers: dict[str, str]) -> str | None:
    """The Cognito sub, or None. Every parse costs money: no token, no parse."""
    settings = get_settings()
    if not settings.auth_configured:
        return None
    scheme, _, token = headers.get("authorization", "").partition(" ")
    if scheme.lower() != "bearer" or not token:
        return None
    try:
        return verify_access_token(token, settings)["sub"]
    except jwt.PyJWTError, ValueError, OSError:
        return None


def _request(event: dict[str, Any]) -> tuple[str, date, str]:
    raw = event.get("body") or ""
    if event.get("isBase64Encoded"):
        raw = base64.b64decode(raw).decode()
    body = json.loads(raw)
    text, today, tz = body["text"], date.fromisoformat(body["today"]), body["tz"]
    if not isinstance(text, str) or not isinstance(tz, str):
        raise ValueError("text and tz must be strings")
    ZoneInfo(tz)  # an unknown zone raises
    return text, today, tz


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    from botocore.exceptions import BotoCoreError, ClientError

    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}
    if event.get("requestContext", {}).get("http", {}).get("method", "POST") != "POST":
        return _error(405, "POST only")
    user = _caller(headers)
    if user is None:
        return _error(401, "sign in to parse an agenda")
    try:
        text, today, tz = _request(event)
    except KeyError, TypeError, ValueError, ZoneInfoNotFoundError:
        return _error(400, 'send {"text": "...", "today": "YYYY-MM-DD", "tz": "Area/City"}')
    if not text.strip():
        return _error(400, "the text is empty")
    if len(text) > MAX_TEXT_CHARS:
        return _error(413, f"the text is longer than {MAX_TEXT_CHARS:,} characters")

    model = get_settings().parser_model
    started = time.monotonic()
    try:
        agenda, usage = parse_agenda(text, today, tz)
    except AgendaParseError as e:
        log.info(
            json.dumps(
                {
                    "event": "agenda_not_found",
                    "user": user,
                    "model": model,
                    "prompt_version": PROMPT_VERSION,
                    **e.usage,
                    "latency_ms": int((time.monotonic() - started) * 1000),
                    "cost_usd": cost_usd(model, e.usage),
                    "error": str(e),
                    "problems": e.problems,
                    "today": today.isoformat(),
                    "tz": tz,
                    "text_chars": len(text),
                }
            )
        )
        return _error(422, str(e))
    except ClientError as e:
        if e.response["Error"]["Code"] == "ThrottlingException":
            log.warning(json.dumps({"event": "agenda_throttled", "user": user, "model": model}))
            return _error(429, "the AI service is busy - try again in a minute")
        log.error(json.dumps({"event": "agenda_bedrock_error", "user": user, "error": repr(e)}))
        return _error(503, "the AI service is unavailable - type the agenda by hand")
    except BotoCoreError as e:  # timeouts, no connection
        log.error(json.dumps({"event": "agenda_bedrock_error", "user": user, "error": repr(e)}))
        return _error(503, "the AI service is unavailable - type the agenda by hand")

    log.info(
        json.dumps(
            {
                "event": "agenda_parsed",
                "user": user,
                "model": model,
                "prompt_version": PROMPT_VERSION,
                **usage,
                "latency_ms": int((time.monotonic() - started) * 1000),
                "cost_usd": cost_usd(model, usage),
                "text_chars": len(text),
                "items": len(agenda.items),
            }
        )
    )
    return _answer(
        200,
        {
            "agenda": agenda.model_dump(mode="json"),
            "model": model,
            "prompt_version": PROMPT_VERSION,
        },
    )
