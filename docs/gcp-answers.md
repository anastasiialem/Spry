# Lab 9 — Spry on Google Cloud: costs and answers

Service choices: [ADR 0006](decisions/0006-google-cloud.md). How to deploy: [README](../README.md#google-cloud-lab-9).

## Part 3 — What it costs

On-demand list prices in USD, AWS `us-east-1`, Google Cloud `us-central1`, 730 hours a month,
no tax. To be checked against the AWS and Google Cloud pricing calculators (links to the saved
estimates go here).

### Spry's core, nobody using it for a month

Spry on AWS is **not** the course's paused Aurora: it is RDS `db.t4g.micro` (ADR 0003), which
cannot pause and restarts by itself seven days after a stop.

| Piece | AWS (this project) | Google Cloud (this project) |
|---|---|---|
| Frontend + CDN + HTTPS | S3 + CloudFront, ~0 traffic → **$0** | Firebase Hosting free plan → **$0** |
| API | Lambda 512 MB, idle → **$0** | Cloud Run 1 vCPU / 512 MiB, scaled to zero → **$0** |
| Database compute | RDS `db.t4g.micro` $0.016/h × 730 → **$11.68** | Cloud SQL `db-f1-micro` $0.0105/h × 730 → **$7.67** (stopped: **$0**) |
| Database storage | 20 GB gp2 × $0.115 → **$2.30** | 10 GB SSD × $0.17 → **$1.70** (billed while stopped too) |
| Secrets | Secrets Manager, 1 secret → **$0.40** | Secret Manager, 1 version → free |
| Registry, logs | ECR < 0.5 GB, CloudWatch → a few cents | Artifact Registry < 0.5 GB, Cloud Logging → free |
| **Total** | **≈ $14.40** | **≈ $9.40**, or **≈ $1.70** with the instance stopped |

Free-tier assumptions: Cloud Run's monthly 2M requests, 180,000 vCPU-s and 360,000 GiB-s;
Lambda's 1M requests and 400,000 GB-s; Firebase Hosting's 10 GB stored and 360 MB/day out
(the built site is ~1 MB); 6 Secret Manager versions; Artifact Registry 0.5 GB; one Cloud SQL
instance, no backups, no HA.

### Four traffic profiles

Busy around the clock = an average of 1 request/s (2.63M a month), 100 ms each. Class demos and
office hours = a few thousand requests, inside every free tier, so only the database line moves.
"Stopped" means the Cloud SQL instance runs only during the profile's hours.

| Profile | DB hours | AWS (RDS) | GCP, Cloud SQL 24/7 | GCP, Cloud SQL stopped when idle | GCP, Firestore |
|---|---|---|---|---|---|
| Nobody | 0 | $14.38 | $9.37 | **$1.70** | **$0** |
| Class demos, 10 × 2 h | 20 | $14.38 | $9.37 | **$1.91** | **$0** |
| Office hours, 8 h × 22 days | 176 | $14.38 | $9.37 | **$3.55** | **$0** |
| Busy around the clock | 730 | $14.38 + Lambda $0.33 = **$14.71** | $9.37 + Cloud Run $2.24 = **$11.61** | = 24/7: **$11.61** | Cloud Run $2.24 + reads $15.33 = **$17.57** |

How the busy line is computed:

- **Lambda:** (2.63M − 1M free) × $0.20/M = $0.33; 2.63M × 0.1 s × 0.5 GB = 131,000 GB-s, inside the free 400,000.
- **Cloud Run:** (2.63M − 2M free) × $0.40/M = $0.25; at most 263,000 vCPU-s of active time
  (no overlap), (263,000 − 180,000) × $0.000024 = $1.99; 131,000 GiB-s, inside the free 360,000. Total $2.24.
- **Firestore:** the list page reads ~20 documents per request: 52.6M reads − 1.5M free
  (50,000 a day) = 51.1M × $0.03/100,000 = $15.33.

**Which cloud is cheaper, and which line decides it?** For this project, **Google Cloud in every
profile**, and the line is always **database compute**. Cloud SQL `db-f1-micro` is a third
cheaper per hour than RDS `db.t4g.micro`, and it can stay stopped as long as you like; RDS
restarts itself after seven days. API, CDN and registry are $0 on both sides until real traffic.

Against the course's reference design (Aurora Serverless v2 at 0–1 ACU, $0.12 per ACU-hour,
0.5 ACU minimum while awake), the answer flips with the profile, and it is still the database line:

| Profile | AWS, Aurora pausing | GCP, Cloud SQL stopped when idle | Cheaper |
|---|---|---|---|
| Nobody | $0.30 | $1.70 | AWS: Aurora pauses, Cloud SQL still pays for its disk |
| Class demos | 20 h × 0.5 × $0.12 + $0.30 = $1.50 | $1.91 | AWS, barely |
| Office hours | 176 h × $0.06 + $0.30 = $10.86 | $3.55 | GCP |
| Busy | 730 h × $0.06 + $0.30 + Lambda $0.33 = $44.43 | $11.61 | GCP: a woken Aurora costs 4–5 × a micro instance |

**Lab 4 showed that Aurora gets more expensive than an instance when something keeps it awake.
Where is the same trap on Google Cloud?**

1. **Cloud Run that never sleeps.** `min_instance_count = 1`, or *instance-based billing*
   (CPU always allocated), bills the instance every second whether requests come or not:
   1 vCPU + 512 MiB around the clock is roughly $45–50 a month, five times the database. A
   health check from an uptime monitor does not do this with request-based billing (only active
   time is billed), but `min_instance_count = 1` "to avoid cold starts" does.
2. **Firestore reads that follow the code.** The busy profile above: the database that costs $0
   idle becomes the most expensive line once a list page reads 20 documents per visit. A
   frontend that polls, or a page that reads a whole collection, spends the daily free 50,000
   reads in minutes.
3. **Cloud SQL that is never stopped.** Not a trap of something waking it up: it is never asleep.
   Stopping it is a decision someone has to make, and the next `terraform apply` with
   `db_activation_policy = "ALWAYS"` starts it again.

## Part 4 — Beyond hosting

### When is Document AI the better tool than a general LLM, and when not?

**Document AI (or Vision OCR) is better** when the input is a *scan or a photo* and the output is
*text and layout*: receipts, invoices, forms, handwritten pages, thousands of pages a month.
It is deterministic (the same page gives the same answer), returns bounding boxes and confidence
per field, costs $1.50 per 1,000 pages for OCR (a page through an LLM with vision costs about
the same or more, and is slower), has fixed processors for forms and tables, and cannot be
prompt-injected by the text on the page.

**A general model is better** when the input is *already text* and the task is *understanding*:
Spry's agenda parser reads a pasted, messy agenda ("after lunch", "Friday at 3 with the team")
and must resolve relative dates, durations and attendee counts into a schema. OCR would return
the same text it got. A custom Document AI extractor would need labelled training documents and
still not reason about "next Friday". The two combine well: Document AI turns a photo of a
printed agenda into text, and the LLM turns that text into meetings.

### Lab 8 on Google Cloud

| Lab 8 on AWS | Google Cloud | What you no longer manage |
|---|---|---|
| S3 with raw JSONL payments | Cloud Storage | — (the same) |
| Glue crawler + Data Catalog, partitions | BigQuery tables (external over GCS, or loaded) | the crawler, re-crawling after new partitions, schema drift by hand |
| Glue job: JSONL → Parquet | Dataflow (the *Text Files on Cloud Storage to BigQuery* template), or a BigQuery `LOAD` / `CREATE TABLE AS SELECT` | the Parquet conversion and the file layout: BigQuery stores columnar data itself |
| Athena queries, billed by data scanned | BigQuery queries, billed by data scanned ($6.25/TiB, 1 TiB free) | the results bucket, workgroups, partition projection |
| Kinesis → Lambda alert (streaming part) | Pub/Sub → Dataflow streaming → BigQuery | shards and their scaling |
| (no dashboard) | Looker Studio over BigQuery, free | — |

## What we discuss in class

**Lock-in.** Unchanged: the container image, FastAPI, SQLAlchemy, Alembic, the PostgreSQL schema,
the React app. Changed: one line in the entrypoint (`$PORT`) and all of the infrastructure code
(Terraform `aws` → `google` provider is a rewrite, not a port). The lock-in is not in compute
(a container runs anywhere) and not in PostgreSQL; it is in the **managed services around them**:
Cognito's user pool and its non-exportable passwords, SES's verified domain, Bedrock's model
access, the S3 report archive, and IAM. A Firestore choice would have moved the lock-in into
the data layer.

**Multicloud.** As a migration state, fine. As a target, Spry's split (site + API + DB on GCP,
sign-in + parser + reports on AWS) costs: a browser that talks to three origins in two clouds;
two IAM systems, two bills, two Terraform workspaces, two sets of logs to search during an
incident; and cross-cloud egress ($0.08–0.12/GB each way) the moment the report builder on AWS
needs the database on GCP. It is worth it only where a service on the other cloud is clearly
better (BigQuery, a model only one cloud has) and the boundary is a narrow API.

**Scale to zero.** Giving up SQL to save ~$9 a month (or ~$1.70 with a stopped instance) is a good
trade only for a new app with simple, query-shaped data and spiky, mostly-idle traffic. For
Spry it is a bad trade: relations, attachments, migrations and every query rewritten, and the
bill grows *faster* than Cloud SQL's once traffic is real (busy profile: $17.57 against $11.61).

**Choosing a cloud.** When both host an API equally well, the deciding factors, in order: what
the team already knows and operates (on-call, IAM, Terraform modules); credits (a $300 or
startup credit decides the first year); a specific service the product needs (BigQuery, a
model, Firebase for a mobile app); and only then list price, which at Spry's size is a few
dollars either way.
