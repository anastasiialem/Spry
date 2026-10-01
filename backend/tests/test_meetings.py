import pytest
from httpx import AsyncClient

VALID = {
    "title": "Weekly sync",
    "starts_at": "2026-10-05T09:00:00Z",
    "ends_at": "2026-10-05T09:30:00Z",
    "attendee_count": 4,
}


async def test_empty_list(client: AsyncClient) -> None:
    response = await client.get("/api/meetings")
    assert response.status_code == 200
    assert response.json() == []


async def test_create_returns_contract_shape(client: AsyncClient) -> None:
    response = await client.post("/api/meetings", json=VALID)
    assert response.status_code == 201
    body = response.json()
    assert isinstance(body["id"], int)
    assert {k: v for k, v in body.items() if k != "id"} == VALID


async def test_offsets_are_normalised_to_utc(client: AsyncClient) -> None:
    payload = VALID | {
        "starts_at": "2026-10-05T12:00:00+03:00",
        "ends_at": "2026-10-05T12:30:00+03:00",
    }
    body = (await client.post("/api/meetings", json=payload)).json()
    assert body["starts_at"] == "2026-10-05T09:00:00Z"
    assert body["ends_at"] == "2026-10-05T09:30:00Z"


async def test_list_is_ordered_by_start(client: AsyncClient) -> None:
    later = VALID | {
        "title": "Later",
        "starts_at": "2026-10-06T09:00:00Z",
        "ends_at": "2026-10-06T10:00:00Z",
    }
    await client.post("/api/meetings", json=later)
    await client.post("/api/meetings", json=VALID)
    titles = [m["title"] for m in (await client.get("/api/meetings")).json()]
    assert titles == ["Weekly sync", "Later"]


@pytest.mark.parametrize(
    "change",
    [
        {"title": "   "},
        {"title": "x" * 201},
        {"ends_at": "2026-10-05T08:00:00Z"},
        {"ends_at": "2026-10-05T09:00:00Z"},
        {"starts_at": "2026-10-05T09:00:00"},
        {"attendee_count": 0},
        {"attendee_count": 1001},
    ],
)
async def test_invalid_payload_is_422(client: AsyncClient, change: dict) -> None:
    response = await client.post("/api/meetings", json=VALID | change)
    assert response.status_code == 422
