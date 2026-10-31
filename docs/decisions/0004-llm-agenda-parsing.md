# 0004 — Paste an agenda: an LLM on Bedrock, in a parser outside the VPC

**Status:** accepted  
**Date:** 2026-10-18 (model changed 2026-10-22)

## Context

Agendas reach people as emails, chat messages and notes, not as forms. "Paste an agenda" takes
that text and turns it into a pre-filled agenda form (items with owner and minutes, action
items with owner and due date) that the user checks and saves.

Constraints:

- **No NAT.** The API and the database live in private subnets with no route to the internet
  (Lab 4). Anything inside the VPC that calls an AWS API needs an endpoint.
- **Cost.** Spry costs ~$0 when idle apart from the database. Every model call costs tokens,
  and an open LLM endpoint is a wallet without a lock.
- **Text from outside.** Pasted emails and invites are written by people other than the user.
  They can contain instructions ("ignore your instructions…"). That text is data.
- **The model can be wrong with a 200.** It can invent an owner or a date that looks right.

## Decision

- **Model:** Mistral Large 3 (`mistral.mistral-large-3-675b-instruct`) on Amazon Bedrock,
  through Bedrock's **Converse API** (`boto3`, `bedrock-runtime`), `temperature: 0`. The plan
  was Claude Opus 5.5, but Bedrock refuses every Anthropic model on this account (see *Why not
  Claude* below). Converse has one request shape for every provider, so the model id is
  configuration (`PARSER_MODEL`): Ministral 3 14B was measured against it, and Claude can
  replace it without a code change once the account may call it
  (`docs/agenda-parser-answers.md`).
- **Contract is a schema.** The model answers by calling one tool, `record_agenda`, whose input
  schema is `ParsedAgenda` (`app/schemas/agenda.py`). Every answer is validated; an invalid one
  goes back to the model once with the validation error, and then the user gets an error.
  "Leave it empty" is both in the prompt and in the schema (`None`).
- **Parser outside the VPC.** `spry-agenda-parser` (`infra/ai.yml`) is the backend image with
  another command, behind its own function URL. It needs Bedrock and Cognito's public keys and
  never the database, so it lives outside the VPC: no NAT, no interface endpoint, $0 when
  nobody parses.
- **The model never writes.** The parser only returns JSON. Saving goes through the existing
  API (`PUT /api/meetings/{id}/agenda`), with its validation and its ownership check. The model's
  answer travels with the save and is stored next to the result (`agendas.ai_suggestion`,
  `ai_model`, `ai_prompt_version`). The difference between them is the quality signal.
- **Guard rails on the endpoint.** A valid Cognito access token is required (401), and text over
  10,000 characters is rejected (413), both before the model is called. One JSON log line per
  parse: user, model, prompt version, tokens, latency, cost.

## Why not Claude

The first version called Claude Opus 5.5 through the Anthropic SDK. On this account every
Anthropic model in every region, including the `us.` and `global.` inference profiles, answers
`AccessDeniedException: … is not available for this account`, and
`get-foundation-model-availability` shows `agreementAvailability: NOT_AVAILABLE`. Upgrading to
the paid plan and submitting Anthropic's use-case form did not change it; other providers
(Amazon Nova, Meta Llama, Mistral) work. The account is a month old, and the error points to
AWS Sales: the restriction is AWS's, and only AWS Support can lift it. The lecturer agreed to
use another model.

Candidates, on the five test inputs through the same prompt and tool
(`docs/agenda-parser-answers.md`):

| Model | Result |
|---|---|
| **Mistral Large 3** | Valid JSON on 5/5 (one retry for a missing UTC offset in the bake-off, none through the parser), weekdays right, even the DST change on 25 October; ignored the injection. $0.50 / $1.50 per 1M tokens. |
| Ministral 3 14B | Cheapest ($0.20 / $0.20), but wrong weekdays, retries on missing offsets, and it obeyed the injection. Kept as the comparison row. |
| Amazon Nova Pro | Valid JSON, but wrong dates and it set every owner to the injected address. |
| Amazon Nova 2 Lite | Wrong UTC offset after the DST change, a date with no time on #3. |
| OpenAI gpt-oss-120b | Ignored the schema: items as plain strings, invalid on 5/5. |

## Alternatives considered

| Alternative | Why it lost |
|---|---|
| Call Bedrock from the API, through a `bedrock-runtime` VPC interface endpoint | ~$7.30 a month per endpoint per AZ, even with no traffic: it breaks "$0 when idle" for a feature that needs no database. The API's 30 s Lambda would also be held by a slow model call. Right for a chat that reads meetings; wrong for a parser. |
| The Claude API directly (api.anthropic.com) instead of Bedrock | Would get Claude despite the Bedrock block, but needs an API key stored and rotated in Secrets Manager, and a second bill outside AWS Budgets. Bedrock uses the function's IAM role (nothing to leak), logs to CloudTrail and bills on the AWS invoice. |
| The Anthropic SDK (Messages API) with Mistral | The Messages API on Bedrock serves Anthropic models only. Converse serves all of them, so switching the model is a config change, not a rewrite. |
| A regular-expression parser | Free and deterministic, but every new format breaks it: "Пн 10:00", "Monday after lunch", numbered lists, inline owners, two languages in one message. Relative dates and free text are exactly what a regex cannot read. |

## Consequences

- **Cost per parse:** about 700–800 input and 100–200 output tokens on Mistral Large 3:
  ~$0.0005–0.0007 (Bedrock on-demand prices, measured with `make parse`; the deployed numbers
  come from the `agenda_parsed` log lines). Claude Opus 5.5 would be ~25× that. A $5 monthly AWS Budgets alarm (net of credits) emails the owner.
- **Logged:** one JSON line per parse in `/aws/lambda/spry-agenda-parser` (`make ai-logs`); the
  pasted text itself is not logged.
- **When Bedrock is down or throttling:** the parser answers 503/429, the screen says so and
  offers "Type it instead". Meetings, agendas, files, sign-in and reports do not depend on
  Bedrock and keep working.
- **Prompt changes are versioned** (`PROMPT_VERSION`), so saved agendas can be compared per
  version.
- **IAM:** `bedrock:InvokeModel` on this region's foundation models, not one model: changing
  `PARSER_MODEL` needs no policy change.
- **Not solved here:** per-user rate limits (one account can still parse all day, up to the
  budget alarm). If AWS Support enables Anthropic models on the account,
  `PARSER_MODEL=anthropic.claude-opus-5-5` is the whole change, after re-running the five
  inputs.
