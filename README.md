# Spry

Meetings, listed and added. FastAPI + PostgreSQL backend, React + Vite frontend, one repository.

The structure, contracts and versions are specified in **[PROJECT.md](PROJECT.md)** — read that
first. Why it is one repository: [docs/decisions/0001-monorepo.md](docs/decisions/0001-monorepo.md).

## Run it

Install Docker Desktop, then:

```bash
docker compose up --build
```

| URL | What |
|---|---|
| http://localhost:5173 | Frontend |
| http://localhost:8000/docs | API docs (Swagger) |
| http://localhost:8000/api/meetings | The list endpoint |

Port taken? Copy `.env.example` to `.env` and change `FRONTEND_PORT`, `BACKEND_PORT` or `POSTGRES_PORT`.

## Everyday commands

```bash
make lint        # ruff + eslint + prettier
make fmt         # auto-format
make test        # backend tests against a real Postgres
make shell-db    # psql
make clean       # stop and wipe the database
make lock        # after changing dependencies: regenerate uv.lock / pnpm-lock.yaml
```

## Deploy

See PROJECT.md §8.
