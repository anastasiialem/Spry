#!/usr/bin/env sh
# Container start: bring the schema up to date, then serve.
# Migrations run here (at start), not at image build time: the build has no database.
set -eu

echo "[entrypoint] alembic upgrade head"
alembic upgrade head

echo "[entrypoint] starting uvicorn $*"
exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --log-level "${LOG_LEVEL:-info}" "$@"
