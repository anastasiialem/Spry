# Prompt used to generate PROJECT.md

Refined from the lab's starting prompt. Changes against the original, and why:

- deployment target named (Lambda + Aurora, S3 + CloudFront) so `infra/` and `scripts/` have a
  stated purpose instead of being unexplained folders;
- the contract asks for exact JSON field names, types, date format and error codes;
- "how it knows the dependency is ready" asks for the concrete healthcheck command;
- an explicit "out of scope" list, because "add nothing" alone still lets auth or nginx creep in.

```text
Write PROJECT.md for a monorepo called "spry". It must describe the structure of the
repository only: folders, what lives in each one, and the contracts between parts.
No implementation code.

Layout:
- backend/  FastAPI, SQLAlchemy 2 (async, asyncpg) as the ORM, Alembic for migrations,
            dependencies managed with uv (pyproject.toml + uv.lock), ruff for lint
- frontend/ React + Vite + TypeScript, Tailwind, shadcn/ui components, ESLint + Prettier,
            pnpm
- docker-compose.yml at the root: postgres, backend, frontend — `docker compose up --build`
  is the only command a new developer runs (they install Docker Desktop first)
- infra/ and scripts/: deployment to AWS — backend as a container image on Lambda behind a
  function URL with Aurora Serverless v2 PostgreSQL; frontend as static files in a private S3
  bucket behind CloudFront; GitHub Actions deploys via OIDC, no access keys
- .github/workflows/: lint on every push, deploy on push to main

Scope of the first slice:
- the backend exposes GET /api/meetings (list) and POST /api/meetings (create one)
- a meeting has: id, title, starts_at, ends_at, attendee count
- the frontend has one page that lists meetings and a form that adds a new one

For every folder state what it is for. For every service in compose state which port it
listens on, what it depends on, and how it knows the dependency is ready (the exact
healthcheck). Define the API contract exactly: JSON field names, types, date format,
ordering, validation rules and status codes for success and errors. State when migrations
run. Pin the versions you choose (base images by tag, never `latest`).

Add nothing that is not listed above. Explicitly out of scope: authentication, Redis or any
cache, message queues, Celery, nginx or any reverse proxy, Kubernetes, a second database,
update/delete endpoints.
```
