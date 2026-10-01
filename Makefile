COMPOSE := docker compose

.PHONY: help lock up down clean logs ps test lint fmt migrate revision shell-db \
	deploy-backend destroy-backend logs-backend migrate-backend \
	cert domain deploy-frontend destroy-frontend github-role

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

# --- local ---

lock: ## Regenerate uv.lock and pnpm-lock.yaml inside containers (after changing dependencies)
	docker run --rm -v "$(CURDIR)/backend:/app" -w /app python:3.14-slim \
		sh -c "pip install -q uv && uv lock"
	docker run --rm -v "$(CURDIR)/frontend:/app" -w /app -e COREPACK_ENABLE_DOWNLOAD_PROMPT=0 node:22-alpine \
		sh -c "corepack enable && pnpm install --lockfile-only"

up: ## Build and start the stack in the foreground
	$(COMPOSE) up --build

down: ## Stop the stack
	$(COMPOSE) down

clean: ## Stop the stack and wipe the database volume
	$(COMPOSE) down -v

logs: ## Tail all logs
	$(COMPOSE) logs -f

ps: ## Service status
	$(COMPOSE) ps

test: ## Backend tests (stack must be running)
	$(COMPOSE) exec backend pytest

lint: ## ruff + eslint + prettier check (stack must be running)
	$(COMPOSE) exec backend ruff check .
	$(COMPOSE) exec backend ruff format --check .
	$(COMPOSE) exec frontend pnpm lint
	$(COMPOSE) exec frontend pnpm format:check

fmt: ## Auto-format both sides
	$(COMPOSE) exec backend ruff check --fix .
	$(COMPOSE) exec backend ruff format .
	$(COMPOSE) exec frontend pnpm format

migrate: ## Apply migrations
	$(COMPOSE) exec backend alembic upgrade head

revision: ## New migration: make revision m="add x"
	$(COMPOSE) exec backend alembic revision --autogenerate -m "$(m)"

shell-db: ## psql into the database
	$(COMPOSE) exec db psql -U $${POSTGRES_USER:-spry} -d $${POSTGRES_DB:-spry}

# --- AWS (part 2 of the lab) ---

deploy-backend: ## Build + push the image, roll the Lambda, migrate, write BACKEND_URL to .env
	./scripts/deploy-backend.sh

destroy-backend: ## Delete the backend stack, Aurora included
	./scripts/destroy-backend.sh

logs-backend: ## Tail the deployed backend's CloudWatch logs
	aws logs tail /aws/lambda/$${PROJECT_NAME:-spry}-backend --follow --since 10m

migrate-backend: ## Re-run migrations on the deployed backend
	aws lambda invoke --function-name $${PROJECT_NAME:-spry}-backend \
		--cli-binary-format raw-in-base64-out --payload '{"action":"migrate"}' /dev/stdout

cert: ## ACM certificate: make cert DOMAIN=app.example.com
	./scripts/domain-frontend.sh cert

domain: ## Custom domain for the frontend: make domain DOMAIN=app.example.com
	./scripts/domain-frontend.sh domain

deploy-frontend: ## vite build against BACKEND_URL -> S3 -> CloudFront invalidation
	./scripts/deploy-frontend.sh

destroy-frontend: ## Delete the bucket and distribution
	./scripts/destroy-frontend.sh

github-role: ## IAM role GitHub Actions assumes via OIDC
	./scripts/github-role.sh
