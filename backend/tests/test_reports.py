"""The weekly report: weeks, the numbers, the CSV, and the builder's handler."""

import csv
import io
import json
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Meeting
from app.reports import lambda_handler, weekly

TZ = "Europe/Kyiv"


def test_parse_week() -> None:
    assert weekly.parse_week("2026-W40").isoformat() == "2026-09-28"
    for bad in ["2026-40", "2026-W00", "2025-W53", "last week", ""]:
        with pytest.raises(ValueError):
            weekly.parse_week(bad)


def test_previous_week_uses_the_local_calendar() -> None:
    # Monday 2026-10-05 00:30 in Kyiv is still Sunday 21:30 in UTC.
    assert weekly.previous_week(datetime(2026, 10, 4, 21, 30, tzinfo=UTC), TZ) == "2026-W40"
    # Across a year boundary: 2026-01-01 is in 2026-W01, the week before is 2025-W52.
    assert weekly.previous_week(datetime(2026, 1, 1, 12, tzinfo=UTC), TZ) == "2025-W52"


def test_week_bounds_and_key() -> None:
    start, end = weekly.week_bounds("2026-W40", TZ)
    assert start.isoformat() == "2026-09-28T00:00:00+03:00"
    assert end - start == timedelta(days=7)
    assert weekly.report_key("2026-W40") == "reports/2026-W40.csv"


def _meeting(owner: str, title: str, start: str, hours: float, people: int = 2) -> Meeting:
    starts = datetime.fromisoformat(start)
    return Meeting(
        owner_sub=owner,
        title=title,
        starts_at=starts,
        ends_at=starts + timedelta(hours=hours),
        attendee_count=people,
    )


async def _seed(session: AsyncSession) -> None:
    session.add_all(
        [
            # 2026-W40 (Mon 28 Sep - Sun 4 Oct, Kyiv time)
            _meeting("alice", "Planning", "2026-09-28T09:00:00+03:00", 2, 5),
            _meeting("alice", "Standup", "2026-09-29T09:00:00+03:00", 0.25),
            _meeting("bob", "Design review", "2026-10-01T14:00:00+03:00", 1.5, 4),
            _meeting("bob", "1:1", "2026-10-02T10:00:00+03:00", 0.5),
            _meeting("alice", "Retro", "2026-10-02T16:00:00+03:00", 1),
            _meeting("bob", "Demo", "2026-10-04T12:00:00+03:00", 0.75, 9),
            # Sunday 21:30 UTC is Monday 00:30 in Kyiv: already W41, left out.
            _meeting("bob", "Late call", "2026-10-04T21:30:00+00:00", 3),
            # 2026-W39
            _meeting("alice", "Kickoff", "2026-09-22T10:00:00+03:00", 1),
            _meeting("bob", "Sync", "2026-09-24T10:00:00+03:00", 1),
        ]
    )
    await session.flush()


async def test_collect(session: AsyncSession) -> None:
    await _seed(session)
    report = await weekly.collect(session, "2026-W40", TZ)

    assert report.current.meetings == 6
    assert report.current.hours == pytest.approx(6.0)
    assert (report.previous.week, report.previous.meetings) == ("2026-W39", 2)
    assert report.previous.hours == pytest.approx(2.0)
    assert [m.title for m in report.longest] == [
        "Planning",
        "Design review",
        "Retro",
        "Demo",
        "1:1",
    ]
    assert report.longest[0].participants == 5
    assert [(o.owner, o.meetings) for o in report.per_owner] == [("alice", 3), ("bob", 3)]


async def test_render_csv(session: AsyncSession) -> None:
    await _seed(session)
    report = await weekly.collect(session, "2026-W40", TZ)
    body = weekly.render_csv(report)
    rows = list(csv.reader(io.StringIO(body.decode())))

    assert ["meetings", "6", "2", "+4"] in rows
    assert ["hours", "6.00", "2.00", "+4.00"] in rows
    assert ["1", "Planning", "2026-09-28 09:00", "2.00", "5"] in rows
    # Same data, same bytes: rebuilding a week rewrites an identical file.
    assert weekly.render_csv(report) == body


async def test_empty_week(session: AsyncSession) -> None:
    report = await weekly.collect(session, "2020-W10", TZ)
    rows = list(csv.reader(io.StringIO(weekly.render_csv(report).decode())))
    assert ["meetings", "0", "0", "+0"] in rows


# --- the builder's handler, without AWS --------------------------------------


def _sqs(*bodies: dict) -> dict:
    return {
        "Records": [{"eventSource": "aws:sqs", "body": json.dumps(body)} for body in bodies]
    }


def test_detect_trigger() -> None:
    assert lambda_handler.detect_trigger({"source": "schedule"}) == "schedule"
    assert lambda_handler.detect_trigger(_sqs({"week": None})) == "sqs"
    assert lambda_handler.detect_trigger({"week": "2026-W40"}) == "direct"


@pytest.fixture
def built(monkeypatch: pytest.MonkeyPatch) -> list[tuple[str, str, bytes]]:
    uploads: list[tuple[str, str, bytes]] = []
    monkeypatch.setattr(lambda_handler, "build_weekly_report", lambda week: week.encode())
    monkeypatch.setattr(lambda_handler, "_upload", lambda *args: uploads.append(args))
    monkeypatch.setenv("REPORTS_BUCKET", "test-bucket")
    lambda_handler.get_settings.cache_clear()
    yield uploads
    lambda_handler.get_settings.cache_clear()


def test_handler_sqs_message_with_a_week(built) -> None:
    result = lambda_handler.handler(_sqs({"week": "2026-W39", "source": "manual"}), None)
    assert result == {"reports": [{"week": "2026-W39", "key": "reports/2026-W39.csv"}]}
    assert built == [("test-bucket", "reports/2026-W39.csv", b"2026-W39")]


def test_handler_no_week_means_previous_week(built) -> None:
    result = lambda_handler.handler({"source": "schedule"}, None)
    assert result["reports"][0]["week"] == weekly.previous_week(timezone=TZ)


def test_handler_rejects_a_bad_week(built) -> None:
    with pytest.raises(ValueError):
        lambda_handler.handler(_sqs({"week": "next tuesday"}), None)
    assert built == []


def test_handler_deliberate_failure(built, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("REPORT_FAIL_WEEK", "2026-W13")
    lambda_handler.get_settings.cache_clear()
    with pytest.raises(RuntimeError, match="deliberate"):
        lambda_handler.handler(_sqs({"week": "2026-W13"}), None)
