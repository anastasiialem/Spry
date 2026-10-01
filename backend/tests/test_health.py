from httpx import AsyncClient


async def test_health(client: AsyncClient) -> None:
    response = await client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


async def test_root_redirects_to_docs(client: AsyncClient) -> None:
    response = await client.get("/")
    assert response.status_code == 307
    assert response.headers["location"] == "/docs"
