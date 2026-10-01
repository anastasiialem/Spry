# syntax=docker/dockerfile:1

# --- builder: resolve locked dependencies into /opt/venv ---
# The venv lives outside /app so the Compose bind mount (./backend:/app) cannot hide it.
FROM python:3.14-slim AS builder

COPY --from=ghcr.io/astral-sh/uv:0.9 /uv /usr/local/bin/uv

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/opt/venv

WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-install-project

# --- dev: what docker-compose.yml runs; adds pytest + ruff and curl for the healthcheck ---
FROM builder AS dev

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-install-project

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

COPY . .
EXPOSE 8000
CMD ["sh", "./scripts/entrypoint.sh", "--reload"]

# --- runtime: production-like container, no dev dependencies, non-root ---
FROM python:3.14-slim AS runtime

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 1000 app

WORKDIR /app
COPY --from=builder /opt/venv /opt/venv
COPY --chown=app:app . .
USER app
EXPOSE 8000
CMD ["sh", "./scripts/entrypoint.sh"]

# --- lambda: what scripts/deploy-backend.sh ships to AWS Lambda ---
FROM public.ecr.aws/lambda/python:3.14 AS lambda

RUN --mount=from=ghcr.io/astral-sh/uv:0.9,source=/uv,target=/bin/uv \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    uv export --frozen --no-dev --no-hashes --no-emit-project -o /tmp/requirements.txt \
    && uv pip install --no-cache --compile-bytecode \
        --target "${LAMBDA_TASK_ROOT}" -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt

COPY app ${LAMBDA_TASK_ROOT}/app
COPY migrations ${LAMBDA_TASK_ROOT}/migrations
COPY alembic.ini ${LAMBDA_TASK_ROOT}/

CMD ["app.lambda_handler.handler"]
