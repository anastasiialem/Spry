from httpx import AsyncClient

MEETING = {
    "title": "Design review",
    "starts_at": "2026-10-05T09:00:00Z",
    "ends_at": "2026-10-05T10:00:00Z",
    "attendee_count": 3,
}
PDF = b"%PDF-1.7 fake pdf bytes"


async def _meeting(client: AsyncClient) -> int:
    return (await client.post("/api/meetings", json=MEETING)).json()["id"]


async def _upload(client: AsyncClient, meeting_id: int, name: str = "agenda.pdf", data=PDF):
    return await client.post(
        f"/api/meetings/{meeting_id}/attachments",
        params={"filename": name},
        content=data,
        headers={"Content-Type": "application/pdf"},
    )


async def test_upload_list_download_delete(client: AsyncClient) -> None:
    meeting_id = await _meeting(client)

    uploaded = await _upload(client, meeting_id)
    assert uploaded.status_code == 201
    body = uploaded.json()
    assert body["filename"] == "agenda.pdf"
    assert body["content_type"] == "application/pdf"
    assert body["size"] == len(PDF)
    assert body["meeting_id"] == meeting_id
    assert body["created_at"].endswith("Z")

    listed = (await client.get(f"/api/meetings/{meeting_id}/attachments")).json()
    assert [a["id"] for a in listed] == [body["id"]]
    meetings = (await client.get("/api/meetings")).json()
    assert meetings[0]["attachment_count"] == 1

    download = await client.get(f"/api/attachments/{body['id']}")
    assert download.status_code == 200
    assert download.content == PDF
    assert download.headers["content-type"] == "application/pdf"
    assert "agenda.pdf" in download.headers["content-disposition"]

    assert (await client.delete(f"/api/attachments/{body['id']}")).status_code == 204
    assert (await client.get(f"/api/attachments/{body['id']}")).status_code == 404
    assert (await client.get(f"/api/meetings/{meeting_id}/attachments")).json() == []


async def test_path_in_filename_is_stripped(client: AsyncClient) -> None:
    meeting_id = await _meeting(client)
    response = await _upload(client, meeting_id, name="../../etc/passwd")
    assert response.json()["filename"] == "passwd"


async def test_non_ascii_filename_round_trips(client: AsyncClient) -> None:
    meeting_id = await _meeting(client)
    attachment = (await _upload(client, meeting_id, name="звіт.pdf")).json()
    download = await client.get(f"/api/attachments/{attachment['id']}")
    assert (
        "filename*=UTF-8''%D0%B7%D0%B2%D1%96%D1%82.pdf" in download.headers["content-disposition"]
    )


async def test_too_large_is_413(client: AsyncClient) -> None:
    meeting_id = await _meeting(client)
    response = await _upload(client, meeting_id, data=b"x" * (4 * 1024 * 1024 + 1))
    assert response.status_code == 413


async def test_empty_or_bad_name_is_422(client: AsyncClient) -> None:
    meeting_id = await _meeting(client)
    assert (await _upload(client, meeting_id, data=b"")).status_code == 422
    assert (await _upload(client, meeting_id, name="..")).status_code == 422


async def test_unknown_meeting_or_attachment_is_404(client: AsyncClient) -> None:
    assert (await _upload(client, 999999)).status_code == 404
    assert (await client.get("/api/meetings/999999/attachments")).status_code == 404
    assert (await client.delete("/api/attachments/999999")).status_code == 404
