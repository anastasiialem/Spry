# 0001 — One repository, not three

**Status:** accepted  
**Date:** 2026-10-01

## Context

Spry has three moving parts in its first slice: a FastAPI backend, a React frontend and a
PostgreSQL schema, plus the CI and deploy scripts that ship them. They can live in three
repositories (`spry-backend`, `spry-frontend`, `spry-infra`) or in one.

## Decision

One repository. `backend/`, `frontend/`, `docker-compose.yml`, `infra/`, `scripts/` and
`.github/workflows/` live side by side in the same tree.

## Why

1. **Atomic changes.** Adding a field to a meeting touches the SQLAlchemy model, an Alembic
   migration, the Pydantic schema and the React form. In one repository that is one commit and
   one pull request; the API and its client cannot drift apart, because they are reviewed and
   deployed together.
2. **The repository is the context window.** An agent working on this code reads the endpoint,
   the model, the migration and the component that renders it in a single pass. Split across
   three repositories it sees a third of the system and guesses the rest — and a guessed
   contract is a bug found at integration time.
3. **One command to start.** `docker compose up --build` from the root builds everything; a new
   developer clones one thing.

## What it costs

- A boundary buys independence: separate repos would let the frontend and backend have
  separate release cadences, permissions and CI. We give that up.
- CI must avoid doing everything on every push (path filters per side).
- The repository grows; at some team size, ownership needs `CODEOWNERS`.

For a team of four and a product that does not exist yet, context is worth more than
independence. We revisit this if separate teams start owning separate services.
