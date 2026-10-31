"""PUT/GET /api/meetings/{id}/agenda: the normal Save, with the parser's suggestion."""

from httpx import AsyncClient

MEETING = {
    "title": "Pricing sync",
    "starts_at": "2026-10-19T07:00:00Z",
    "ends_at": "2026-10-19T07:45:00Z",
    "attendee_count": 3,
}
SUGGESTED = {
    "title": "синк по прайсингу",
    "starts_at": "2026-10-19T10:00:00+03:00",
    "duration_minutes": 45,
    "items": [
        {"topic": "нові тарифи Pro", "owner": "Олена", "minutes": 15},
        {"topic": "фідбек від клієнтів", "owner": "Taras", "minutes": None},
    ],
    "action_items": [{"task": "порівняння з конкурентами", "owner": "Taras", "due": "2026-10-23"}],
    "language": "uk",
}


async def _meeting(client: AsyncClient) -> str:
    created = await client.post("/api/meetings", json=MEETING)
    return f"/api/meetings/{created.json()['id']}/agenda"


async def test_no_agenda_yet_is_404(client: AsyncClient) -> None:
    url = await _meeting(client)
    assert (await client.get(url)).status_code == 404


async def test_typed_agenda_round_trips(client: AsyncClient) -> None:
    url = await _meeting(client)
    body = {"items": [{"topic": "  Roadmap  ", "minutes": 20}]}
    saved = await client.put(url, json=body)
    assert saved.status_code == 200
    assert saved.json()["items"] == [{"topic": "Roadmap", "owner": None, "minutes": 20}]
    assert saved.json()["action_items"] == []
    assert saved.json()["ai_model"] is None
    assert (await client.get(url)).json() == saved.json()


async def test_suggestion_is_stored_next_to_the_correction(client: AsyncClient, session) -> None:
    url = await _meeting(client)
    corrected = {
        "items": [
            {"topic": "нові тарифи Pro", "owner": "Олена", "minutes": 15},
            {"topic": "фідбек від клієнтів", "owner": "Тарас", "minutes": 10},
        ],
        "action_items": SUGGESTED["action_items"],
        "ai_suggestion": {
            "agenda": SUGGESTED,
            "model": "anthropic.claude-opus-5-5",
            "prompt_version": "agenda-v1",
        },
    }
    saved = (await client.put(url, json=corrected)).json()
    assert saved["items"][1]["owner"] == "Тарас"
    assert saved["ai_model"] == "anthropic.claude-opus-5-5"
    assert saved["ai_prompt_version"] == "agenda-v1"

    from app.models import Agenda

    row = await session.get(Agenda, saved["meeting_id"])
    assert row.ai_suggestion["items"][1]["owner"] == "Taras"  # what the model said

    # Saving again by hand replaces the whole agenda and forgets the suggestion.
    retyped = (await client.put(url, json={"items": [{"topic": "Only this"}]})).json()
    assert retyped["ai_model"] is None
    await session.refresh(row)
    assert row.ai_suggestion is None


async def test_invalid_agendas_are_422(client: AsyncClient) -> None:
    url = await _meeting(client)
    for body in (
        {"items": [{"topic": ""}]},
        {"items": [{"topic": "x", "minutes": 0}]},
        {"items": [{"topic": "x", "extra": 1}]},
        {"items": [], "action_items": [{"task": "x", "due": "Friday"}]},
        {
            "items": [],
            "ai_suggestion": {"agenda": {"items": []}, "model": "m", "prompt_version": "v"},
        },
    ):
        assert (await client.put(url, json=body)).status_code == 422, body


async def test_unknown_meeting_is_404(client: AsyncClient) -> None:
    assert (await client.put("/api/meetings/999999/agenda", json={"items": []})).status_code == 404
