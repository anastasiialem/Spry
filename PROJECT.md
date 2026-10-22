# Spry — PROJECT.md

This file is the **specification of the repository's structure**: folders, what lives in each,
and the contracts between them. It contains no implementation. Every file in the repository is
generated from it, so a mistake here is a mistake everywhere — change this file first, then the
code.

Why one repository and not three: see [`docs/decisions/0001-monorepo.md`](docs/decisions/0001-monorepo.md).

---

## 1. Scope of the first slice

- The backend exposes `GET /api/meetings` (list), `POST /api/meetings` (create one),
  `PATCH /api/meetings/{id}` (edit any field), `DELETE /api/meetings/{id}` and file attachments per meeting (upload, list,
  download, delete).
- A meeting has: `id`, `title`, `starts_at`, `ends_at`, `attendee_count`, `status`, and
  zero or more attachments (≤ 4 MB each).
- The frontend has one page that lists meetings, a form that adds a new one, a status
  picker per meeting, a schedule panel, and a side panel to edit a meeting and manage its
  files.
- Sign-in (Lab 3): Amazon Cognito managed login with email + password (self sign-up on) and
  "Continue with Google"; the header shows who is signed in. See §9.
- `docker compose up --build` is the only command a new developer runs (after installing
  Docker Desktop).

**Out of scope — do not add:** sharing meetings between users, roles/admins, deleting meetings, object storage (S3) for attachments, Redis or any
cache, Celery/RQ or self-hosted workers (background work is the AWS-managed weekly report in
§10 only), nginx or any reverse proxy, Kubernetes, a second database, server-side rendering.

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
│   ├── auth.yaml                  # Cognito user pool, Google IdP, public app client, managed login
│   ├── backend.yaml               # ECR image → Lambda + function URL, RDS PostgreSQL 17, VPC wiring
│   ├── frontend.yaml              # private S3 bucket + CloudFront (+ ACM cert / custom domain)
│   └── github-oidc.yaml           # IAM role GitHub Actions assumes via OIDC (no access keys)
│
├── scripts/                       # imperative glue the Makefile calls; each one is idempotent
│   ├── deploy-auth.sh             # auth stack (Google secret as a NoEcho parameter, never in git)
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

**Authentication.** Every `/api/*` route needs `Authorization: Bearer <Cognito access token>`;
`/`, `/health` and `/docs` stay public. The API checks the RS256 signature against the pool's
JWKS (cached for an hour, refetched on an unknown `kid`; on Lambda passed in as `COGNITO_JWKS`
because the function has no internet route), `exp`, `iss`, `token_use == "access"` and
`client_id`. Missing or bad token → `401` with `WWW-Authenticate: Bearer`.
No pool configured: development and tests run as the single user `local-dev`; production
answers `503` — a missing setting never leaves the API open.

**Ownership.** Each meeting stores its creator's Cognito `sub` (`owner_sub`); every query is
scoped to the caller. Someone else's meeting or attachment answers `404`, exactly like a
missing one, so ids reveal nothing.

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

### `DELETE /api/meetings/{id}`
Deletes the meeting with its agenda and attachments (`ON DELETE CASCADE`). `204`; unknown `id`
(or another user's) → `404 {"detail": "Meeting not found"}`. The meeting panel's 🗑 button asks
for confirmation first.

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

### Agenda
One agenda per meeting; saving replaces it. Same ownership rule: someone else's meeting → `404`.

| Method | Path | Body | Success | Errors |
|---|---|---|---|---|
| `GET` | `/api/meetings/{id}/agenda` | — | `200` `Agenda` | `404` meeting or no agenda yet |
| `PUT` | `/api/meetings/{id}/agenda` | `AgendaWrite` | `200` `Agenda` | `404` meeting, `422` invalid |

```jsonc
// AgendaWrite (request)
{
  "items": [{"topic": "New Pro tiers", "owner": "Olena", "minutes": 15}],   // 0..50; topic 1..500, owner ≤200 or null, minutes 1..480 or null
  "action_items": [{"task": "Competitor comparison", "owner": "Taras", "due": "2026-10-23"}],  // 0..50
  "ai_suggestion": {                    // optional: the parser's answer the form started from
    "agenda": { /* ParsedAgenda, exactly as the parser returned it */ },
    "model": "mistral.mistral-large-3-675b-instruct",
    "prompt_version": "agenda-v1"
  }
}
// Agenda (response)
{ "meeting_id": 1, "items": [...], "action_items": [...],
  "ai_model": "mistral.mistral-large-3-675b-instruct" | null, "ai_prompt_version": "agenda-v1" | null,
  "updated_at": "2026-10-18T12:00:00Z" }
```

### Database table `meetings`

| Column | Type | Constraint |
|---|---|---|
| `id` | `integer` | primary key, identity |
| `title` | `varchar(200)` | not null |
| `starts_at` | `timestamptz` | not null, indexed |
| `ends_at` | `timestamptz` | not null, `CHECK (ends_at > starts_at)` |
| `attendee_count` | `integer` | not null, `CHECK (attendee_count BETWEEN 1 AND 1000)` |
| `status` | `varchar(20)` | not null, default `'not_started'`, `CHECK (status IN ('not_started','in_progress','done'))` |
| `owner_sub` | `varchar(64)` | not null, indexed — Cognito `sub` of the creator (`0004_meeting_owner`; older rows become `'unclaimed'`) |

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

### Database table `agendas`

| Column | Type | Constraint |
|---|---|---|
| `meeting_id` | `integer` | primary key, FK → `meetings.id` `ON DELETE CASCADE` |
| `items` | `jsonb` | not null — `[{topic, owner, minutes}]` |
| `action_items` | `jsonb` | not null, default `[]` — `[{task, owner, due}]` |
| `ai_suggestion` | `jsonb` | null — the parser's `ParsedAgenda` before the user's corrections |
| `ai_model` / `ai_prompt_version` | `varchar(100)` / `varchar(40)` | null — who suggested it |
| `updated_at` | `timestamptz` | not null, default `now()` |

Created by Alembic revisions `0001_create_meetings`, `0002_meeting_status` (adds `status`;
existing rows become `not_started`), `0003_attachments`, `0004_meeting_owner` and `0005_agendas`. `Base.metadata.create_all()` is used only
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

---

## 9. Sign-in (Amazon Cognito)

```
browser ─/login/─> Cognito managed login (spry-anastasiia.auth.us-east-1.amazoncognito.com)
                     ├─ email + password (sign-up, email code)
                     └─ Continue with Google ──> Google ──> Cognito /oauth2/idpresponse
        <─ /auth/callback/?code=&state= ── code + PKCE verifier exchanged for tokens in the browser
```

- **`infra/auth.yaml`** (stack `spry-auth`, `make deploy-auth`): user pool (sign-in with email,
  email auto-verified, self sign-up on, Essentials tier), Google identity provider (scopes
  `openid email profile`, `email`/`email_verified`/`name` mapped), a **public** app client
  (no secret, code flow, PKCE), domain prefix `spry-anastasiia` with managed login v2 and the
  default branding plus a page background image (`infra/assets/login-background.jpg`, applied by
  `deploy-auth.sh` through the managed-login branding API). Sign-up asks for email, password and
  a **username** (`preferred_username`, required; for Google users it is mapped from their name).
- **Callback URLs** (exact, trailing slash): `<origin>/auth/callback/` and logout `<origin>/login/`
  (signing out lands back on the sign-in page) and `<origin>/` for
  `https://app.spry.pp.ua`, the CloudFront name and `http://localhost:5173`.
- **Secrets:** `GOOGLE_CLIENT_SECRET` lives in `.env` (gitignored) and goes to CloudFormation as a
  `NoEcho` parameter. The frontend needs no secret: authority, client id and domain are public
  and come from the stack's outputs at build time (`deploy-frontend.sh`), never by copy-paste.
- **Frontend:** `react-oidc-context` + `oidc-client-ts`.
  - `/login/` starts the redirect (`signinRedirect()`); this is the URL to hand out, because the
    library must store `state` and the PKCE verifier before leaving the site.
  - `/auth/callback/` exchanges the code and returns to `/`.
  - Header: **Sign in** / **Google** (skips Cognito's page via `identity_provider=Google`) when
    signed out; username · email + **Sign out** when signed in. Sign-out clears the local session, then
    goes to Cognito's `/logout?client_id=…&logout_uri=…` (Cognito has no OIDC end-session).
  - `/privacy/` — privacy policy linked from Google's consent screen.
- A build without the Cognito variables (plain `docker compose up` before `make deploy-auth`)
  simply has no sign-in.
- **The meetings page requires sign-in** (when the build has Cognito settings): signed out, it
  shows a "Sign in" prompt instead of data. Every API call sends the **access token** (read from
  the session `oidc-client-ts` keeps in `localStorage`); file downloads are fetched with the
  token and saved, because a plain link cannot carry it.
- **Backend:** `app/auth.py` verifies the token (see §4); `deploy-backend.sh` reads the pool id
  and client id from the `spry-auth` stack and passes the pool's JWKS to the Lambda.
- **One email, one account:** a Cognito pre sign-up trigger (`LinkAccountsFunction` in
  `infra/auth.yaml`) links the first Google sign-in to an existing password account with the
  same email, so both ways sign in as the same user (same `sub`, same meetings). It links only
  when the email is verified on both sides (Google's `email_verified`, and the code the
  password user confirmed). A password sign-up for an email that already uses Google is
  refused with a hint to use "Sign in with Google".

## 10. Weekly meetings report (event-driven, AWS)

Every Monday 07:00 Europe/Kyiv the system builds last week's report, saves it to S3 and emails
it. Nobody clicks anything. Template `infra/reports.yaml`, deployed by `make deploy-reports`
(after `make deploy-backend`; it reads the VPC, subnets, security group, image and database URL
from the `spry-backend` stack).

```
EventBridge Scheduler ─┐  {"week": null, "source": "schedule"}       (command)
make report-now ───────┴─> SQS report-requests ──(3 receives)──> report-requests-dlq
                                 │ event source mapping, BatchSize 1
                                 v
                 report-builder Lambda (backend image, in the VPC)
                   reads RDS, writes reports/<week>.csv via the S3 gateway endpoint
                                 │ s3:ObjectCreated (prefix reports/, suffix .csv)   (event)
                                 v
                 report-mailer Lambda (inline Python, outside the VPC) ──> SES ──> inbox
```

- **The report** — `app/reports/weekly.py`, `build_weekly_report(week) -> bytes`, no AWS in it.
  For one ISO week (Monday–Sunday in Europe/Kyiv, all accounts): number of meetings and total
  hours, the same for the week before and the change, the five longest meetings (title, start,
  duration, participants = `attendee_count`), totals per account (`owner_sub`).
  The week is always a parameter; the file is always `reports/<week>.csv`, and the CSV carries
  no build timestamp, so rebuilding a week overwrites one identical file (idempotent).
  Locally: `make report-local WEEK=2026-W40`.
- **Builder** — `app/reports/lambda_handler.py`, same image as the API with
  `ImageConfig.Command`. Accepts a direct invocation (`{"source": "schedule"}`) or an SQS event;
  no week means the previous ISO week. Logs
  `report-builder triggered trigger=<sqs|schedule|direct> source=<schedule|manual> week=<w>`.
  `make deploy-backend` also rolls it to the new image.
- **Queue** — visibility timeout 360 s = 6 × the builder's 60 s timeout; after 3 receives a
  message moves to the DLQ (kept 14 days). `make report-now WEEK=…` sends
  `{"week": "…", "source": "manual"}`.
- **Mailer** — logs `report-mailer triggered trigger=s3 event=ObjectCreated:Put object=…`, reads
  the file (s3:GetObject only — it never writes to `reports/`), sends it with
  `sesv2.send_email` (raw MIME, CSV attached) from `reports@<domain>` to `REPORT_RECIPIENTS`.
- **SES** — domain identity with DKIM (three CNAMEs at nic.ua); the account is in the sandbox,
  so the recipient is verified as a second identity.
- **Bucket** — `<project>-reports-<account>`, private, SSE-S3, objects under `reports/` expire
  after 90 days. The name is built, not `!GetAtt`, to avoid the bucket ↔ permission cycle.
- **Lab switches** (in `.env`, then `make deploy-reports`): `REPORT_SCHEDULE="rate(5 minutes)"`
  for a test run of the schedule; `REPORT_FAIL_WEEK=2026-W13` makes that one week fail, to watch
  it reach the DLQ. Unset both afterwards.
- **Commands** — `make report-now`, `make report-ls`, `make report-logs`, `make report-dlq`.

## 11. Paste an agenda (an LLM on Amazon Bedrock)

The user pastes an email, a chat message or notes into a meeting; a model on Bedrock turns it into a
structured agenda; the app shows the normal agenda form pre-filled; the user checks it and
saves. The model suggests, the person decides. Why it is built this way:
[`docs/decisions/0004-llm-agenda-parsing.md`](docs/decisions/0004-llm-agenda-parsing.md);
diagram: [`docs/architecture.md`](docs/architecture.md).

```
browser ──POST {text, today, tz} + access token──> agenda-parser Lambda (function URL, no VPC)
                                                      │ token? ≤10,000 chars? → Bedrock (Converse)
                                                      │ record_agenda tool → validate ParsedAgenda (1 retry)
        <── {agenda, model, prompt_version} ──────────┘ one JSON log line: tokens, latency, cost
browser ──PUT /api/meetings/{id}/agenda (+ ai_suggestion)──> API (VPC) ──> RDS
```

- **Parser** — `app/ai/agenda.py`, `parse_agenda(text, today, tz)`; no Lambda or database in it.
  Model from `PARSER_MODEL` (default `mistral.mistral-large-3-675b-instruct`; Claude is not
  available on this account, ADR 0004), Bedrock's Converse API through `boto3`
  (`bedrock-runtime`, 10 s read timeout, 2 retries), `temperature: 0`. Any Bedrock model with
  tool use works unchanged. The model must answer with the `record_agenda` tool (no forced tool
  choice, which Opus 5.5 rejects, so the prompt asks for it). Invalid output is sent back once with the validation error; no tool call, or no items and
  no action items, is "no agenda found". `PROMPT_VERSION = "agenda-v1"`.
- **Lambda** — `app/ai/agenda_lambda.py`, the backend image with `ImageConfig.Command`, 512 MB,
  30 s, outside the VPC (`infra/ai.yml`, stack `spry-ai`, `make deploy-ai`). Role:
  `bedrock:InvokeModel` on this region's foundation models. Verifies the Cognito access token with the pool's
  JWKS (fetched: it has internet). Answers `200`, `400` bad body, `401` token, `413` > 10,000
  chars, `422` no agenda, `429` Bedrock throttling, `503` Bedrock unavailable. CORS (POST,
  `authorization`, `content-type`) is on the function URL, for `API_CORS_ORIGINS` +
  `http://localhost:5173`. Log line: `{"event": "agenda_parsed", "user", "model",
  "prompt_version", "input_tokens", "output_tokens", "latency_ms", "cost_usd", ...}`; the
  pasted text is not logged. `make deploy-backend` rolls it to each new image.
- **Screen** — the meeting panel's **Agenda** section: **Paste an agenda** (text area, character
  count, Parse; while waiting a seconds counter and **Cancel**, via `AbortController`) or
  **Add agenda / Edit** by hand. The result is the agenda form with every model-filled field
  marked *suggested* until touched; empty stays empty. Suggested meeting title/time are shown
  with an opt-in "Also update the meeting" checkbox (PATCH through the normal API). Save is
  always `PUT /api/meetings/{id}/agenda`, carrying the untouched suggestion. Each error has its
  own message and "Type it instead". `VITE_PARSER_URL` (from the `spry-ai` stack, build time);
  empty hides the paste box.
- **Budget** — AWS Budgets `spry-monthly`, $5, net of credits, emails `BUDGET_EMAIL` (default:
  the first `REPORT_RECIPIENTS`) on actual > 100 % and forecast > 100 %.
- **Commands** — `make llm-hello` (first call from the laptop), `make parse TEXT="..."` (one
  parse: JSON, usage, cost; `PARSER_MODEL=... make parse` to compare), `make deploy-ai`,
  `make ai-logs`. Laptop commands run in the backend container with `~/.aws` mounted read-only.
