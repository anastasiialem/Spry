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

Two roads, one per kind of change:

- **The application** (API image, site): GitHub Actions on every push to `main`
  (`.github/workflows/deploy.yml`, the same `make deploy-backend` / `make deploy-frontend` you can
  run locally). See PROJECT.md §8.
- **The infrastructure** (sign-in, weekly report, agenda parser): Terraform in [`infra/`](infra),
  planned and applied by **HCP Terraform** (organization `ooad-anastasiialem`, workspace
  `spry-dev`). A pull request that touches `infra/` gets a plan as a check, and a merge to `main`
  applies it. Nobody applies from a laptop. Why: [docs/decisions/0005-terraform.md](docs/decisions/0005-terraform.md).

When a change needs both (say, a new environment variable for a Lambda), merge the
infrastructure first, wait for *Apply finished*, then merge the code.

### Infrastructure from a laptop: read and plan only

```bash
brew install hashicorp/tap/terraform   # 1.10 or newer
terraform login                        # once: stores an HCP Terraform API token
make infra-init                        # connect infra/ to the spry-dev workspace
make infra-plan                        # speculative plan, runs in HCP Terraform
make infra-output                      # what exists: pool id, client id, parser URL, ...
make infra-env                         # copy public outputs to .env, print Google/DKIM settings
make auth-branding                     # sign-in page background (after the pool exists)
```

| File | What |
|---|---|
| `infra/auth.tf` | Cognito user pool, Google IdP, web client, managed login, link-accounts trigger |
| `infra/reports.tf` | Schedule → SQS → builder Lambda → S3 → mailer Lambda → SES |
| `infra/ai.tf` | Agenda-parser Lambda, its function URL, the monthly budget alarm |
| `infra/data.tf` | What it reads from the CloudFormation stacks that remain (`backend.yaml`, `frontend.yaml`) |
| `infra/terraform.tfvars` | Non-secret inputs. `google_client_secret` is a sensitive variable in the workspace |

The HCP workspace has `TFC_AWS_PROVIDER_AUTH=true` and `TFC_AWS_RUN_ROLE_ARN` (dynamic
credentials through OIDC, no AWS keys), and the sensitive Terraform variable
`google_client_secret`. CI reads outputs with the `TF_API_TOKEN` repository secret.
