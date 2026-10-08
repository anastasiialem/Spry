# 0003 — RDS PostgreSQL instead of Aurora Serverless v2

**Status:** accepted (supersedes the Aurora choice inherited from the course template)  
**Date:** 2026-10-01

## Context

The course template deploys Postgres as Aurora Serverless v2 (scales to zero, private VPC,
password auth). The AWS account for this lab is on the **Free plan**, which rejects that:

> To use Aurora clusters with free plan accounts you need to set WithExpressConfiguration.

Aurora *express configuration* is not a drop-in: the cluster cannot live in a VPC, is reached
over the public internet through an "internet access gateway", and accepts IAM auth tokens
only (no password). The account is needed for one or two labs, so upgrading the plan is not
worth it.

## Decision

Run PostgreSQL 17 on a single **RDS `db.t4g.micro`** instance (20 GB gp2, single-AZ, private
subnets, reachable only from the Lambda's security group).

## Why

- **Nothing else changes.** Same VPC layout, same password-based `DATABASE_URL`, same
  migrations, same code. Swapping Aurora for RDS is two resources in `infra/backend.yaml`.
- **Same engine as local.** `postgres:17-alpine` in Compose ↔ RDS PostgreSQL 17 on AWS.
- **Cheap and predictable.** db.t4g.micro is $0.016/h (~$11.7/month) + 20 GB gp2 (~$2.3). The
  12-month RDS free tier applies only to accounts created before 15 July 2025; this account is
  newer, so the instance is paid from the sign-up credits.
- **Private stays private.** Express Aurora would put the database on the internet behind IAM
  tokens; a lab app gains nothing from that exposure.

## What it costs

- No scale-to-zero: the instance bills 24/7 (~$14/month from the credits) whether anyone uses
  the app or not - tear it down with `make destroy-backend` after the course.
- Single-AZ, no automatic failover; ~80 connections max, which is why the Lambda opens a
  connection per request (`DB_POOLING=false`) instead of pooling per environment.

## When to revisit

On a paid account, or when availability matters: Aurora Serverless v2 (template version in git
history) or Multi-AZ RDS.
