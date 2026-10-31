"""Entry point of the report-builder Lambda.

The same container image as the API, started with another command
(image_config.command in infra/reports.tf), so it gets the models, the
database code and build_weekly_report for free.

Two shapes of event arrive here:

- a direct invocation with the request itself, e.g. ``{"source": "schedule"}``
  (step 3 of the lab, or ``aws lambda invoke`` by hand);
- an SQS event, one request per record in ``Records[i]["body"]`` (step 4: the
  schedule and ``make report-now`` both send to the report-requests queue).

A request is ``{"week": "2026-W40" | null, "source": "..."}``; no week means
the previous ISO week. Any exception fails the invocation: for SQS the message
comes back after the visibility timeout, and after three receives it moves to
the dead-letter queue.
"""

import json
import logging
from typing import Any

from app.config import get_settings
from app.reports.weekly import build_weekly_report, parse_week, previous_week, report_key

log = logging.getLogger("spry.report_builder")
# Lambda's runtime puts a handler on the root logger; this lets INFO through.
log.setLevel(logging.INFO)


def detect_trigger(event: dict[str, Any]) -> str:
    """What started this invocation: "sqs", "schedule" or "direct"."""
    records = event.get("Records") or []
    if records and records[0].get("eventSource") == "aws:sqs":
        return "sqs"
    if event.get("source") == "schedule":
        return "schedule"
    return "direct"


def requests_in(event: dict[str, Any]) -> list[dict[str, Any]]:
    if detect_trigger(event) == "sqs":
        return [json.loads(record.get("body") or "{}") for record in event["Records"]]
    return [event]


def _upload(bucket: str, key: str, body: bytes) -> None:
    import boto3  # in the Lambda base image; not needed to build a report locally

    boto3.client("s3").put_object(
        Bucket=bucket, Key=key, Body=body, ContentType="text/csv; charset=utf-8"
    )


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    settings = get_settings()
    trigger = detect_trigger(event)
    done = []
    for request in requests_in(event):
        week = request.get("week") or previous_week(timezone=settings.report_timezone)
        source = request.get("source") or trigger
        log.info("report-builder triggered trigger=%s source=%s week=%s", trigger, source, week)

        parse_week(week)  # a malformed week fails here, and ends up in the DLQ
        if settings.report_fail_week and week == settings.report_fail_week:
            raise RuntimeError(f"deliberate failure for {week} (REPORT_FAIL_WEEK)")
        if not settings.reports_bucket:
            raise RuntimeError("REPORTS_BUCKET is not set")

        body = build_weekly_report(week)
        key = report_key(week)
        _upload(settings.reports_bucket, key, body)
        log.info(
            "report-builder wrote s3://%s/%s (%d bytes)", settings.reports_bucket, key, len(body)
        )
        done.append({"week": week, "key": key})
    return {"reports": done}
