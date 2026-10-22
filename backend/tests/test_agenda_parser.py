"""The parser function with a fake model, and its Lambda handler."""

import json
from datetime import date

import pytest

from app import auth
from app.ai import agenda as parser
from app.ai import agenda_lambda
from app.config import get_settings
from tests.test_auth import CLIENT, POOL, _jwks, token

GOOD = {
    "title": "синк по прайсингу",
    "starts_at": "2026-10-19T10:00:00+03:00",
    "duration_minutes": 45,
    "items": [{"topic": "нові тарифи Pro", "owner": "Олена", "minutes": 15}],
    "action_items": [{"task": "порівняння з конкурентами", "owner": "Taras", "due": "2026-10-23"}],
    "language": "uk",
}


def _reply(tool_input=None, stop_reason="tool_use"):
    """A Converse response, as boto3 returns it."""
    content = []
    if tool_input is not None:
        content.append(
            {"toolUse": {"toolUseId": "tooluse_1", "name": "record_agenda", "input": tool_input}}
        )
    return {
        "output": {"message": {"role": "assistant", "content": content}},
        "stopReason": stop_reason,
        "usage": {"inputTokens": 1000, "outputTokens": 200},
    }


class FakeModel:
    """Answers with the given replies in order and remembers every request."""

    def __init__(self, *replies):
        self.replies = list(replies)
        self.requests = []

    def converse(self, **request):
        self.requests.append(json.loads(json.dumps(request)))
        return self.replies.pop(0)


def test_valid_answer_is_returned_with_usage() -> None:
    model = FakeModel(_reply(GOOD))
    agenda, usage = parser.parse_agenda("text", date(2026, 10, 18), "Europe/Kyiv", client=model)
    assert agenda.items[0].owner == "Олена"
    assert usage == {"input_tokens": 1000, "output_tokens": 200}
    request = model.requests[0]
    assert "toolChoice" not in request["toolConfig"]  # Opus 5.5 rejects a forced tool
    assert request["toolConfig"]["tools"][0]["toolSpec"]["name"] == "record_agenda"
    prompt = request["messages"][0]["content"][0]["text"]
    assert "Sunday 2026-10-18" in prompt and "Europe/Kyiv" in prompt
    assert "<pasted_text>\ntext\n</pasted_text>" in prompt


def test_invalid_answer_is_shown_to_the_model_once() -> None:
    bad = GOOD | {"starts_at": "2026-10-19T10:00:00"}  # no offset
    model = FakeModel(_reply(bad), _reply(GOOD))
    agenda, usage = parser.parse_agenda("text", date(2026, 10, 18), "Europe/Kyiv", client=model)
    assert agenda.starts_at == GOOD["starts_at"]
    assert usage == {"input_tokens": 2000, "output_tokens": 400}
    feedback = model.requests[1]["messages"][-1]["content"][0]["toolResult"]
    assert feedback["toolUseId"] == "tooluse_1" and feedback["status"] == "error"
    assert "UTC offset" in feedback["content"][0]["text"]


def test_invalid_twice_gives_up() -> None:
    model = FakeModel(_reply({"items": "none"}), _reply({"items": "none"}))
    with pytest.raises(parser.AgendaParseError, match="twice") as failed:
        parser.parse_agenda("text", date(2026, 10, 18), "UTC", client=model)
    assert failed.value.problems[0].startswith("items: ")
    assert len(failed.value.problems) >= 2  # both answers


def test_no_tool_call_is_an_error() -> None:
    model = FakeModel(_reply(None, stop_reason="content_filtered"))
    with pytest.raises(parser.AgendaParseError, match="content_filtered"):
        parser.parse_agenda("text", date(2026, 10, 18), "UTC", client=model)


def test_nothing_found_is_an_error() -> None:
    model = FakeModel(_reply({"items": [], "language": "en"}))
    with pytest.raises(parser.AgendaParseError, match="no agenda"):
        parser.parse_agenda("milk, eggs", date(2026, 10, 18), "UTC", client=model)


def test_cost() -> None:
    usage = {"input_tokens": 1_500, "output_tokens": 500}
    assert parser.cost_usd("mistral.mistral-large-3-675b-instruct", usage) == 0.0015
    assert parser.cost_usd("mistral.ministral-3-14b-instruct", usage) == 0.0004
    assert parser.cost_usd("anthropic.claude-opus-5-5", usage) == 0.016
    assert parser.cost_usd("anthropic.claude-haiku-5-5", usage) == 0.0004
    assert parser.cost_usd("amazon.nova-micro-v1:0", usage) is None


# --- the Lambda handler ----------------------------------------------------------


@pytest.fixture
def pool(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("COGNITO_USER_POOL_ID", POOL)
    monkeypatch.setenv("COGNITO_CLIENT_ID", CLIENT)
    monkeypatch.setenv("COGNITO_JWKS", _jwks())
    get_settings.cache_clear()
    auth.reset_key_cache()
    yield
    get_settings.cache_clear()
    auth.reset_key_cache()


def _event(body, headers=None):
    return {
        "requestContext": {"http": {"method": "POST"}},
        "headers": headers if headers is not None else token("alice"),
        "body": json.dumps(body),
        "isBase64Encoded": False,
    }


BODY = {"text": "Пн 10:00, синк", "today": "2026-10-18", "tz": "Europe/Kyiv"}


def test_handler_parses_and_logs_one_line(pool, monkeypatch, caplog) -> None:
    monkeypatch.setattr(parser, "_client", FakeModel(_reply(GOOD)))
    caplog.set_level("INFO", logger="spry.agenda_parser")
    answer = agenda_lambda.handler(_event(BODY), None)
    assert answer["statusCode"] == 200
    body = json.loads(answer["body"])
    assert body["agenda"]["items"][0]["topic"] == "нові тарифи Pro"
    assert body["prompt_version"] == "agenda-v1"

    line = json.loads(caplog.records[-1].getMessage())
    assert line["event"] == "agenda_parsed" and line["user"] == "alice"
    assert line["model"] == "mistral.mistral-large-3-675b-instruct"
    assert {"input_tokens", "output_tokens", "latency_ms", "cost_usd"} <= line.keys()
    assert line["cost_usd"] == 0.0008


@pytest.mark.parametrize(
    ("headers", "body", "status"),
    [
        ({}, BODY, 401),
        ({"Authorization": "Bearer nope"}, BODY, 401),
        (None, {"text": "x"}, 400),
        (None, BODY | {"tz": "Mars/Olympus"}, 400),
        (None, BODY | {"text": "   "}, 400),
        (None, BODY | {"text": "x" * 10_001}, 413),
    ],
)
def test_handler_rejects_before_calling_the_model(pool, monkeypatch, headers, body, status) -> None:
    model = FakeModel()
    monkeypatch.setattr(parser, "_client", model)
    assert agenda_lambda.handler(_event(body, headers), None)["statusCode"] == status
    assert model.requests == []


def test_handler_without_a_pool_is_401(monkeypatch) -> None:
    monkeypatch.setattr(parser, "_client", FakeModel())
    get_settings.cache_clear()
    assert agenda_lambda.handler(_event(BODY), None)["statusCode"] == 401


def test_handler_no_agenda_is_422(pool, monkeypatch) -> None:
    monkeypatch.setattr(parser, "_client", FakeModel(_reply(None, stop_reason="end_turn")))
    assert agenda_lambda.handler(_event(BODY), None)["statusCode"] == 422


@pytest.mark.parametrize(
    ("code", "status"), [("ThrottlingException", 429), ("AccessDeniedException", 503)]
)
def test_handler_bedrock_errors(pool, monkeypatch, code, status) -> None:
    from botocore.exceptions import ClientError

    class Failing(FakeModel):
        def converse(self, **request):
            raise ClientError({"Error": {"Code": code, "Message": "no"}}, "Converse")

    monkeypatch.setattr(parser, "_client", Failing())
    assert agenda_lambda.handler(_event(BODY), None)["statusCode"] == status
