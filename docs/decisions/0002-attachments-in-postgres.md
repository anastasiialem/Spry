# 0002 — Meeting attachments are stored in Postgres, not S3

**Status:** accepted  
**Date:** 2026-10-01

## Context

Meetings get file attachments. A file has to be stored somewhere both locally
(`docker compose up`) and on AWS (Lambda + RDS PostgreSQL). The two usual places are the database
(`bytea` column) or object storage (S3, with presigned URLs).

## Decision

Store the bytes in a `bytea` column of an `attachments` table, ≤ 4 MB per file, uploaded as
the raw request body.

## Why

- **Same code everywhere.** Locally there is no S3; with files in Postgres, Compose needs no
  extra service (an S3 emulator would be exactly the "add nothing" creep PROJECT.md forbids),
  and AWS needs no bucket, IAM policy or VPC endpoint for the Lambda — it already reaches the database.
- **One transaction.** A file and its row are written and deleted together; deleting a
  meeting cascades to its files. With S3 a crash between the two writes leaves orphans.
- **Backups and migrations already cover it.**

## What it costs

- Every byte passes through Lambda: the request limit (6 MB, base64-encoded) caps files at
  4 MB, and large downloads cost Lambda time.
- Database storage is dearer than S3 and the table grows the backups.
- `data` must never be loaded by list queries — the column is `deferred` in the ORM.

## When to revisit

When files larger than a few MB are needed, or attachments become a large share of the
database: move to S3 with presigned upload/download URLs, keep the `attachments` table as
metadata (`s3_key` instead of `data`), and migrate existing rows with a one-off script.
