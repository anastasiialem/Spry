# Spry — containers (C4, level 2)

What runs where, and which arrow carries what. Updated for "Paste an agenda"
([ADR 0004](decisions/0004-llm-agenda-parsing.md)): the **parse** path goes browser → parser →
Bedrock and touches no data; the **save** path is the normal browser → API → database one.

```mermaid
C4Container
  title Spry - container diagram

  Person(user, "Team lead", "Plans meetings and their agendas")

  System_Ext(cognito, "Amazon Cognito", "Sign-in: email + password, Google")
  System_Ext(bedrock, "Amazon Bedrock", "Mistral Large 3, Converse API")
  System_Ext(ses, "Amazon SES", "Sends the weekly report")

  System_Boundary(spry, "Spry (AWS, us-east-1)") {
    Container(spa, "Web app", "React, Vite; S3 + CloudFront", "Meetings, agenda form, Paste an agenda")
    Container(parser, "Agenda parser", "Python Lambda + function URL, outside the VPC", "Text -> validated agenda JSON. Reads and writes nothing")
    Container(api, "API", "FastAPI on Lambda + function URL, in the VPC", "Meetings, agendas, files; owner-scoped")
    ContainerDb(db, "Database", "RDS PostgreSQL 17, private subnets", "meetings, agendas (+ ai_suggestion), attachments")
    Container(reports, "Weekly report", "Scheduler -> SQS -> builder Lambda -> S3 -> mailer Lambda", "Monday CSV by email")
  }

  Rel(user, spa, "Uses", "HTTPS")
  Rel(spa, cognito, "Signs in", "OIDC code + PKCE")
  Rel(spa, parser, "1. parse: pasted text", "HTTPS POST, access token")
  Rel(parser, bedrock, "record_agenda tool call", "HTTPS, IAM role")
  Rel(spa, api, "2. save: PUT /api/meetings/{id}/agenda", "HTTPS JSON, access token")
  Rel(api, db, "Reads/writes", "SQL")
  Rel(reports, db, "Reads", "SQL")
  Rel(reports, ses, "Sends", "SES API")

  UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")
```

Plain-text version:

```
                      ┌──────────── parse (suggests only) ────────────┐
browser ──HTTPS──> agenda-parser Lambda (no VPC) ──IAM──> Bedrock (Mistral Large 3)
   │                  checks token, ≤10k chars, validates JSON, logs tokens + cost
   │
   └──HTTPS──> API Lambda (VPC) ──SQL──> RDS PostgreSQL
                  PUT /api/meetings/{id}/agenda  (the only write; stores ai_suggestion too)
```
