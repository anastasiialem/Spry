# Spry — PROJECT.md

This file is the **specification of the repository's structure**: folders, what lives in each,
and the contracts between them. It contains no implementation. Every file in the repository is
generated from it, so a mistake here is a mistake everywhere — change this file first, then the
code.

Why one repository and not three: see [`docs/decisions/0001-monorepo.md`](docs/decisions/0001-monorepo.md).

---

## 1. Scope of the first slice

- The backend exposes `GET /api/meetings` (list), `POST /api/meetings` (create one),
  `PATCH /api/meetings/{id}` (edit any field) and file attachments per meeting (upload, list,
  download, delete).
- A meeting has: `id`, `title`, `starts_at`, `ends_at`, `attendee_count`, `status`, and
  zero or more attachments (≤ 4 MB each).
- The frontend has one page that lists meetings, a form that adds a new one, a status
  picker per meeting, a schedule panel, and a side panel to edit a meeting and manage its
  files.
- `docker compose up --build` is the only command a new developer runs (after installing
  Docker Desktop).

**Out of scope — do not add:** authentication, users, deleting meetings, object storage (S3) for attachments, Redis or any
cache, message queues, Celery or background workers, nginx or any reverse proxy, Kubernetes,
a second database, server-side rendering.

---

## 2. Repository layout

```
spry/                              (repository root)
├── PROJECT.md                     # this specification
├── README.md                      # how to run it; points here for structure
├── .env.example                   # every variable Compose and the scripts read; committed
├── .gitignore                     # .env, node_modules, .venv, build output
├── docker-compose.yml             # local stack: db, backend, frontend
├── Makefile                       # the commands humans and CI both run (up, lint, deploy-*)
│
├── docs/
│   ├── decisions/                 # architecture decision records (why, not how)
│   └── prompts/                   # the prompts this repo was generated from
│
├── .github/workflows/
│   ├── lint.yml                   # ruff + eslint + prettier on every push and PR
│   └── deploy.yml                 # on push to main: lint, then make deploy-backend / deploy-frontend
│
├── infra/                         # CloudFormation templates — the AWS resources, declared
│   ├── backend.yaml               # ECR image → Lambda + function URL, RDS PostgreSQL 17, VPC wiring
│   ├── frontend.yaml              # private S3 bucket + CloudFront (+ ACM cert / custom domain)
│   └── github-oidc.yaml           # IAM role GitHub Actions assumes via OIDC (no access keys)
│
├── scripts/                       # imperative glue the Makefile calls; each one is idempotent
│   ├── deploy-backend.sh          # build image → push to ECR (tag = git SHA) → update stack → migrate
│   ├── deploy-frontend.sh         # vite build against BACKEND_URL → s3 sync → CloudFront invalidation
│   ├── domain.sh                  # ACM certificate (DNS-validated) + the CNAMEs to add for app./api.
│   ├── destroy-*.sh               # tear down what deploy created
│   └── github-role.sh             # create/update the OIDC role
│
├── backend/                       # the API; nothing outside this folder imports its Python
│   ├── Dockerfile                 # stages: builder → dev (Compose), runtime, lambda (AWS)
│   ├── pyproject.toml, uv.lock    # dependencies, exact versions locked
│   ├── alembic.ini
│   ├── app/
│   │   ├── main.py                # FastAPI app factory: CORS, /health, routers
│   │   ├── config.py              # Settings from environment (pydantic-settings); nothing reads os.environ
│   │   ├── db.py                  # async engine, session factory, get_session dependency
│   │   ├── lambda_handler.py      # Lambda entry: HTTP via Mangum; {"action":"migrate"} runs Alembic
│   │   ├── api/meetings.py        # HTTP layer: parse, validate, call service, map to status codes
│   │   ├── api/attachments.py     # HTTP layer for files: raw-body upload, download, delete
│   │   ├── schemas/               # Pydantic request/response models = the API contract in code
│   │   ├── services/              # business logic and queries; no HTTP types here
│   │   └── models/                # SQLAlchemy ORM models = the tables (meeting, attachment)
│   ├── migrations/                # Alembic env + versions/; the only way the schema changes
│   ├── scripts/entrypoint.sh      # container start: alembic upgrade head → uvicorn
│   └── tests/                     # pytest against a real Postgres
│
└── frontend/                      # the UI; talks to the backend only over HTTP (§4)
    ├── Dockerfile                 # node image running the Vite dev server for Compose
    ├── package.json, pnpm-lock.yaml
    ├── vite.config.ts             # React plugin, Tailwind plugin, "@/..." alias
    ├── index.html                 # Vite entry
    ├── public/images/             # cover, schedule background and flower decorations
    ├── components.json            # shadcn/ui CLI config
    ├── eslint.config.js, .prettierrc
    └── src/
        ├── main.tsx               # mounts <App/> with the QueryClientProvider
        ├── App.tsx                # the single page: header, meeting list, add form
        ├── index.css              # Tailwind import + shadcn theme variables
        ├── components/
        │   ├── ui/                # generated by `shadcn add`; not edited by hand
        │   ├── meeting-stats.tsx  # week-over-week callouts (§5)
        │   ├── meeting-table.tsx  # database view of GET /api/meetings
        │   ├── meeting-form.tsx   # posts to POST /api/meetings
        │   ├── meeting-fields.tsx # the shared title + property inputs and client-side validation
        │   ├── meeting-peek.tsx   # side panel: edit a meeting, upload/download/delete attachments
        │   ├── status-select.tsx  # Notion-style status pill; PATCHes /api/meetings/{id}
        │   └── schedule.tsx       # right-hand panel: week strip + the selected day's agenda
        └── lib/
            ├── api.ts             # the only module that calls fetch; zod schemas mirror §4
            ├── week-stats.ts      # pure functions: week boundaries and the three metrics
            ├── meeting-validation.ts # form rules mirroring §4, UTC <-> datetime-local conversion
            └── utils.ts           # cn() helper from shadcn
```

**Boundary rule:** the only contract between `frontend/` and `backend/` is the HTTP API in §4.
Neither imports the other's code.

---

## 3. Local stack — `docker-compose.yml`

One Compose file, three services on the default network, one named volume `pgdata`.

| Service | Image / build | Listens on (container → host) | Depends on | How it knows the dependency is ready |
|---|---|---|---|---|
| `db` | `postgres:17-alpine` | `5432 → ${POSTGRES_PORT:-5432}` | — | its own healthcheck: `pg_isready -U $POSTGRES_USER -d $POSTGRES_DB`, every 5 s, 10 retries |
| `backend` | `build: ./backend` (target `dev`, base `python:3.14-slim`) | `8000 → ${BACKEND_PORT:-8000}` | `db` | `depends_on: db: condition: service_healthy`; own healthcheck `curl -fsS http://localhost:8000/health` |
| `frontend` | `build: ./frontend` (base `node:22-alpine`) | `5173 → ${FRONTEND_PORT:-5173}` | `backend` | `depends_on: backend: condition: service_healthy` |

**Startup order is explicit, not assumed:** `depends_on` alone orders container *start*; the
`condition: service_healthy` lines make each service wait until the previous one *answers*.

**Migrations run at container start**, not at build time: `backend/scripts/entrypoint.sh` runs
`alembic upgrade head`, then starts Uvicorn. A fresh volume comes up with the `meetings` table.
On AWS the same migration runs once per deploy by invoking the Lambda with `{"action":"migrate"}`.

**If the database disappears later** (no Compose feature helps): the engine uses
`pool_pre_ping`, so the next request gets a fresh connection; while the DB is down requests
fail with `503` instead of hanging, and `restart: unless-stopped` restarts a crashed container.

**Development-only lines** (wrong in production): the published `db` port, the bind mounts
`./backend:/app` and `./frontend:/app`, `uvicorn --reload`, the Vite dev server, the default
`spry`/`spry` credentials.

---

## 4. API contract

Base URL: `http://localhost:8000` locally, `https://api.<domain>` deployed. JSON only,
`Content-Type: application/json`. Errors use FastAPI's shape `{"detail": ...}`.

### `GET /`
`307` redirect to `/docs` (Swagger UI), so the bare API address is never a 404. Not in the
OpenAPI schema.

### `GET /health`
`200 {"status": "ok"}` — liveness; touches no dependencies. Used by Compose healthchecks.

### `GET /api/meetings`
`200` with a JSON **array** of `Meeting`, ordered by `starts_at` ascending, then `id`.
No pagination in this slice. Empty table → `[]`.

### `POST /api/meetings`
Request body `MeetingCreate`; response `201` with the created `Meeting`.
Invalid body → `422` with FastAPI's validation `detail` list.

### `PATCH /api/meetings/{id}`
Request body: any non-empty subset of `MeetingCreate`'s fields, e.g.
`{"starts_at": "...", "ends_at": "..."}` or `{"status": "done"}`. Fields not sent keep their
value; `null` is not allowed; unknown fields → `422`. After merging, the same rules as create
apply (`ends_at > starts_at`, etc.) → otherwise `422`.
`200` with the updated `Meeting`; unknown `id` → `404 {"detail": "Meeting not found"}`.

### Attachments
Files are uploaded as the **raw request body** (not multipart) — the browser sends the `File`
object directly, and the server needs no form-parsing dependency.

| Method | Path | Body | Success | Errors |
|---|---|---|---|---|
| `GET` | `/api/meetings/{id}/attachments` | — | `200` `Attachment[]`, oldest first | `404` meeting |
| `POST` | `/api/meetings/{id}/attachments?filename=report.pdf` | file bytes; `Content-Type` = the file's type | `201` `Attachment` | `404` meeting, `413` > 4 MB, `422` empty body or bad filename |
| `GET` | `/api/attachments/{attachment_id}` | — | `200` the bytes, `Content-Type` as uploaded, `Content-Disposition: attachment; filename*=UTF-8''…` | `404` |
| `DELETE` | `/api/attachments/{attachment_id}` | — | `204` | `404` |

```jsonc
// Attachment
{
  "id": 7,
  "meeting_id": 1,
  "filename": "agenda.pdf",            // basename only, 1..255 chars
  "content_type": "application/pdf",   // as sent; "application/octet-stream" if missing
  "size": 48213,                        // bytes, 1..4194304
  "created_at": "2026-10-01T11:20:00Z"
}
```

The 4 MB limit keeps uploads under Lambda function URLs' 6 MB request limit after base64.
Why files live in Postgres and not S3: [`docs/decisions/0002-attachments-in-postgres.md`](docs/decisions/0002-attachments-in-postgres.md).

```jsonc
// MeetingCreate (request)
{
  "title": "Weekly sync",                    // string, 1..200 chars after trimming, required
  "starts_at": "2026-10-05T09:00:00Z",       // string, ISO 8601 with timezone, required
  "ends_at":   "2026-10-05T09:30:00Z",       // string, ISO 8601 with timezone, must be > starts_at
  "attendee_count": 4,                       // integer, 1..1000, required
  "status": "not_started"                    // optional: "not_started" | "in_progress" | "done"
}

// Meeting (response) = MeetingCreate + id
{
  "id": 1,                                   // integer, assigned by the database
  "title": "Weekly sync",
  "starts_at": "2026-10-05T09:00:00Z",       // always returned in UTC with "Z"
  "ends_at":   "2026-10-05T09:30:00Z",
  "attendee_count": 4,
  "status": "not_started",
  "attachment_count": 0                      // read-only, number of attachments
}
```

Datetimes without a timezone are rejected (`422`); the client always sends UTC.

### Database table `meetings`

| Column | Type | Constraint |
|---|---|---|
| `id` | `integer` | primary key, identity |
| `title` | `varchar(200)` | not null |
| `starts_at` | `timestamptz` | not null, indexed |
| `ends_at` | `timestamptz` | not null, `CHECK (ends_at > starts_at)` |
| `attendee_count` | `integer` | not null, `CHECK (attendee_count BETWEEN 1 AND 1000)` |
| `status` | `varchar(20)` | not null, default `'not_started'`, `CHECK (status IN ('not_started','in_progress','done'))` |

### Database table `attachments`

| Column | Type | Constraint |
|---|---|---|
| `id` | `integer` | primary key, identity |
| `meeting_id` | `integer` | not null, FK → `meetings.id` `ON DELETE CASCADE`, indexed |
| `filename` | `varchar(255)` | not null |
| `content_type` | `varchar(127)` | not null |
| `size` | `integer` | not null, `CHECK (size BETWEEN 1 AND 4194304)` |
| `data` | `bytea` | not null; loaded only when the file is downloaded |
| `created_at` | `timestamptz` | not null, default `now()` |

Created by Alembic revisions `0001_create_meetings`, `0002_meeting_status` (adds `status`;
existing rows become `not_started`) and `0003_attachments`. `Base.metadata.create_all()` is used only
in tests.

---

## 5. Frontend behaviour

One page (`/`), laid out like a Notion page; colours from a deep-green coffeehouse palette
(tokens in `src/index.css`, no third-party logos or wordmarks).

- **Top bar:** breadcrumb `Spry / Meetings`.
- **Layout:** two columns from `lg` (≥1024 px): the page on the left, the schedule panel
  (320 px, sticky) on the right; below `lg` the panel moves under the page.
- **Page header:** a cover photo (swans on a green pond, `public/images/swans.jpg`), a
  flower page icon (`magnolia.png`, transparent background) under it, the title "Meetings"
  and a one-line description. No emoji icon.
- **Decoration:** the same flower appears small in the schedule panel's corner and as a
  divider at the end of the page; decorations are `aria-hidden` and never cover text.
- **Week-over-week callouts** (three Notion-style callout blocks), computed in the browser from
  the `GET /api/meetings` response — no extra endpoint. Weeks run Monday 00:00 → Monday 00:00
  in the browser's time zone; a meeting belongs to the week its `starts_at` falls in.
  - *Meetings this week* — count, and the difference against last week (`+2 vs last week`).
  - *Hours in meetings* — sum of `ends_at − starts_at`, one decimal, with the difference.
  - *Average attendees* — mean `attendee_count` this week, with the difference.
  Increases are shown in green, decreases in muted red, no change as "same as last week".
- **Database view:** a table with columns Title, Status, Date, Time, Duration, Attendees;
  a 📎 count next to the title when a meeting has files; clicking a title (or a meeting in
  the schedule) opens the side panel; a "New"
  button above it (Notion's position) opens the add form as an inline block above the table;
  "+ New meeting" also sits as the table's last row. Meetings that have ended are shown muted;
  the next upcoming one is marked "Next".
- **Status:** a Notion-style pill — *Not started* (grey), *In progress* (amber), *Done*
  (green). Clicking it opens the native select; choosing a value PATCHes the meeting, updates
  the row immediately and rolls back with an error message if the request fails. The form
  has the same Status property (default *Not started*).
- **Side panel ("peek"):** slides in from the right over a dimmed page; Esc, the × button or a
  click on the backdrop closes it. Top: the same fields as the create form, pre-filled; "Save
  changes" sends only the fields that changed (`PATCH`). Below: "Files" — a list (name,
  size, download link, delete), and "Upload file" (any type, ≤ 4 MB, checked in the browser
  before sending).
- **Schedule panel:** background photo of white tulips (`tulips.jpg`) at low opacity under a
  light wash, so text keeps its contrast; a week strip (Mon–Sun) with ‹ › to move between weeks and a "Today"
  button; days with meetings carry a dot; the selected day (default: today) lists its
  meetings in time order on a vertical time rail — start–end time, title, attendees, and a
  colour bar for the status. Empty day → "Nothing scheduled".
- **States:** loading → skeleton rows; empty → an empty-state row with a call to action;
  failed fetch → an error alert with a Retry button.
- **Form:** title, start, end, attendees. Submitting calls `POST`, then refetches the list and
  closes the form; validation errors are shown under the field. The form converts the
  browser's local time to UTC before sending.
- Reloading the page shows the same meetings — they come from Postgres, not from memory.
- shadcn components used: `button card input label alert skeleton table`.
- The week-over-week callouts do not depend on status.

---

## 6. Configuration

All configuration is environment variables. `.env.example` is committed; `.env` is ignored.

| Variable | Used by | Local default |
|---|---|---|
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` | db | `spry` / `spry` / `spry` |
| `DATABASE_URL` | backend | `postgresql+asyncpg://spry:spry@db:5432/spry` |
| `CORS_ORIGINS` | backend | `http://localhost:5173` (comma-separated) |
| `VITE_API_URL` | frontend, **build time** | `http://localhost:8000` |
| `AWS_REGION`, `PROJECT_NAME`, `DOMAIN_NAME`, `BACKEND_URL` | scripts | `us-east-1`, `spry`, —, — |

`VITE_API_URL` is inlined into the bundle when Vite builds, so the deployed frontend is built
against the deployed API URL.

---

## 7. Pinned versions

| Thing | Version |
|---|---|
| PostgreSQL (local) | `postgres:17-alpine` — matches RDS PostgreSQL 17 on AWS |
| Python | `python:3.14-slim` (Compose), `public.ecr.aws/lambda/python:3.14` (Lambda) |
| Node | `node:22-alpine`, pnpm 10 via corepack |
| Backend libraries | FastAPI, SQLAlchemy 2.0, Alembic 1, asyncpg, pydantic-settings 2, Mangum — exact versions in `uv.lock` |
| Frontend libraries | React 19, Vite, Tailwind CSS 4, TypeScript 5, zod 4, TanStack Query 5 — exact versions in `pnpm-lock.yaml` |
| Lint | ruff (backend), ESLint 9 + Prettier 3 (frontend) |

Lockfiles are committed; Docker builds install with `--frozen` / `--frozen-lockfile`.

---

## 8. Deployment (AWS, us-east-1)

```
browser ──HTTPS──> app.<domain> ─> CloudFront ─> private S3 bucket (static Vite build)
browser ──HTTPS──> api.<domain> ─> CloudFront ─> Lambda function URL ─> FastAPI (Mangum) ─> RDS PostgreSQL (private subnets)
```

- `make deploy-backend` — build the `lambda` image, push to ECR tagged with the git SHA,
  update the CloudFormation stack, run migrations, write `BACKEND_URL` to `.env`.
- `make deploy-frontend` — `vite build` with `VITE_API_URL=$BACKEND_URL`, `aws s3 sync`,
  CloudFront invalidation.
- Custom domain: ACM certificates (us-east-1), validated by DNS CNAME; `app.` and `api.`
  pointed at their CloudFront distributions.
- CI: `.github/workflows/deploy.yml` on push to `main` runs lint, then the same `make` targets,
  with credentials from OIDC (`aws-actions/configure-aws-credentials@v4`), trust policy limited
  to `repo:<owner>/<repo>:ref:refs/heads/main`.
