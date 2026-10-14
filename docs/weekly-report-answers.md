# Weekly report — answers (Part 3, Step 7)

Spry, `infra/reports.yaml`. Prices: us-east-1, on-demand, October 2026; a month = 730 h.

## What we observed

- **Same week built many times → one file.** With the schedule at `rate(5 minutes)` the builder
  rebuilt `2026-W41` five times. `aws s3 ls` still shows one `reports/2026-W41.csv` (638 bytes):
  the key is derived from the week and the CSV has no build timestamp, so the builder is
  idempotent.
- **…but one email attempt per build.** Every one of those PutObjects produced its own
  `ObjectCreated:Put` event and its own mailer invocation (a different request id each time).
  Sending the same week twice gives **two emails**: overwriting a file is a new event, and the
  mailer has no memory of what it already sent. Writing the file is idempotent; sending an email
  is not.
- **DLQ.** With `REPORT_FAIL_WEEK=2026-W13` the builder failed at 15:55, 16:01 and 16:07 UTC —
  6 minutes apart, the queue's visibility timeout — and after the third receive the message moved
  to `spry-report-requests-dlq`. After removing the failure and running *Start DLQ redrive*,
  `reports/2026-W13.csv` was written on the next attempt.
- **S3 → Lambda retries on its own.** While SES was not verified yet, every mailer invocation
  failed with `MessageRejected` and S3's asynchronous invoke ran it twice more (3 attempts per
  event). Another reason the mailer must tolerate duplicates.

## 1. The same ObjectCreated event twice → two identical emails. Where to store "already sent"?

In a **DynamoDB table** (`sent_reports`), written with a **conditional put** *before* sending:

- **Key:** `bucket/key#etag`, e.g. `spry-reports-…/reports/2026-W40.csv#9b2c…`. The ETag is the
  MD5 of the content. So a duplicate delivery of the same event, or a rebuild that produced
  exactly the same bytes, is skipped. A rebuild with *different* numbers (a meeting was edited)
  has a new ETag and is sent again — which is what a person wants.
  To suppress only duplicate *deliveries*, key on the event's `s3.object.sequencer` instead.
- `PutItem … ConditionExpression="attribute_not_exists(pk)"`: of two concurrent invocations
  exactly one wins, the other gets `ConditionalCheckFailed` and stops. Store
  `status=sending`, set `sent` after SES answers, and delete the item if sending fails, so a retry
  can try again. Add a TTL of ~100 days to clean up.
- **Why not the RDS database:** the mailer runs outside the VPC and cannot reach it — that is
  the whole point of the split. DynamoDB has a public endpoint, needs no VPC, and this volume is
  inside its free tier. (Not the S3 object's metadata either: changing it is a copy, which is
  another `ObjectCreated` event.)

## 2. The builder in the VPC cannot reach SES — three fixes and their cost

| Fix | Monthly cost | Notes |
|---|---|---|
| **NAT gateway** | ~$32.85 (0.045 $/h) + 0.045 $/GB | Opens the whole internet to the VPC. Needs a public subnet and route changes; one per AZ for HA (×2–3). |
| **Interface VPC endpoint for the SES API** (supported since December 2025; SMTP had one earlier) | ~$7.30 per AZ (0.01 $/h) + 0.01 $/GB → ~$14.60 for 2 AZs | Only SES becomes reachable. The function's subnets must be in the AZs that have the endpoint. |
| **The split we built** (builder in the VPC → S3 event → mailer outside) | ≈ $0 | Lambda, S3 requests and notifications are free-tier-sized; the S3 gateway endpoint is free. |

SES itself costs $0.10 per 1,000 emails in every option.

- **Ten more emails a week:** the split. It costs nothing and the network cost of the other two
  does not depend on volume.
- **A million emails a week:** still the split. SES (~$100/week) dominates whichever path the
  bytes take, and a NAT or endpoint only adds to it. At that scale the real work is elsewhere:
  SES production access and sending quota, a queue in front of the mailer to control throughput,
  bounce/complaint handling, and the deduplication table above. If one function really had to
  do everything inside the VPC, the SES interface endpoint beats NAT: cheaper per hour and per GB,
  and it opens only SES.

## 3. A link that works for a week instead of an attachment

A presigned URL lives no longer than the credentials that signed it. A Lambda role's credentials
expire after a few hours, so the link dies with them, whatever `ExpiresIn` says. Options:

- **Best: link to the app, not to S3.** Email `https://app.spry.pp.ua/reports/2026-W40`. The page
  requires sign-in (Cognito, as in Lab 3), and the API creates a fresh presigned URL valid for a
  few minutes at the moment of the click and redirects to it. The link in the email never
  expires, and it is useless to anyone who is not signed in. Presigning is local computation, so
  the API needs no network path to S3 to do it — only the browser downloads the file.
- **CloudFront signed URL** (a key group on a distribution in front of the bucket, OAC). It is
  signed with a CloudFront key pair, not with role credentials, and can carry any expiry, e.g.
  7 days. The private key belongs in Secrets Manager or SSM, read by the mailer.
- **SigV4 presign with long-lived IAM user keys** reaches the 7-day maximum, but it means a
  permanent access key stored somewhere — exactly what this project avoids. Not recommended.
