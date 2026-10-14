"""The weekly meetings report: one ISO week in, one CSV out.

No AWS in this module. Two rules the rest of the pipeline relies on:

- The week is a parameter. Nothing here says "last week"; the caller decides,
  so an old report can be rebuilt at any time.
- The same week always maps to the same file name (``reports/2026-W40.csv``).
  Building a week twice overwrites one file instead of creating two, which is
  what makes "at least once" delivery from SQS harmless.

Run it against the Compose database:  make report-local WEEK=2026-W40
"""

import asyncio
import csv
import io
import re
import sys
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from datetime import time as dtime
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

from app.config import get_settings
from app.models import Meeting

WEEK_PATTERN = re.compile(r"^(\d{4})-W(\d{2})$")
TOP_N = 5


# --- weeks ------------------------------------------------------------------


def parse_week(week: str) -> date:
    """Turn "2026-W40" into the Monday of that ISO week; ValueError otherwise."""
    match = WEEK_PATTERN.match(week or "")
    if not match:
        raise ValueError(f"not an ISO week like 2026-W40: {week!r}")
    # Also rejects W00, and W53 in a year that has only 52 weeks.
    return date.fromisocalendar(int(match[1]), int(match[2]), 1)


def iso_week(day: date) -> str:
    year, week, _ = day.isocalendar()
    return f"{year}-W{week:02d}"


def shift_week(week: str, weeks: int) -> str:
    return iso_week(parse_week(week) + timedelta(weeks=weeks))


def previous_week(now: datetime | None = None, timezone: str = "Europe/Kyiv") -> str:
    """The ISO week before the one ``now`` falls in, by the local calendar."""
    today = (now or datetime.now(UTC)).astimezone(ZoneInfo(timezone)).date()
    return iso_week(today - timedelta(weeks=1))


def week_bounds(week: str, timezone: str) -> tuple[datetime, datetime]:
    """[Monday 00:00, next Monday 00:00) in the report's timezone."""
    zone = ZoneInfo(timezone)
    monday = parse_week(week)
    start = datetime.combine(monday, dtime.min, zone)
    return start, datetime.combine(monday + timedelta(days=7), dtime.min, zone)


def report_key(week: str) -> str:
    parse_week(week)
    return f"reports/{week}.csv"


# --- data -------------------------------------------------------------------


@dataclass(frozen=True)
class Totals:
    week: str
    meetings: int
    hours: float


@dataclass(frozen=True)
class LongMeeting:
    title: str
    starts_at: datetime
    hours: float
    participants: int


@dataclass(frozen=True)
class OwnerTotals:
    owner: str
    meetings: int
    hours: float


@dataclass(frozen=True)
class WeeklyReport:
    week: str
    timezone: str
    current: Totals
    previous: Totals
    longest: list[LongMeeting]
    per_owner: list[OwnerTotals]


def _hours(meeting: Meeting) -> float:
    return (meeting.ends_at - meeting.starts_at).total_seconds() / 3600


async def _meetings_in(session: AsyncSession, week: str, timezone: str) -> list[Meeting]:
    start, end = week_bounds(week, timezone)
    result = await session.scalars(
        select(Meeting)
        .where(Meeting.starts_at >= start, Meeting.starts_at < end)
        .order_by(Meeting.starts_at, Meeting.id)
    )
    return list(result.all())


def _totals(week: str, meetings: list[Meeting]) -> Totals:
    return Totals(week, len(meetings), sum(_hours(m) for m in meetings))


async def collect(session: AsyncSession, week: str, timezone: str) -> WeeklyReport:
    """Everything the report shows, for one week, across all accounts."""
    before = shift_week(week, -1)
    current = await _meetings_in(session, week, timezone)
    previous = await _meetings_in(session, before, timezone)

    longest = sorted(current, key=lambda m: (-_hours(m), m.starts_at, m.id))[:TOP_N]

    owners: dict[str, list[Meeting]] = {}
    for meeting in current:
        owners.setdefault(meeting.owner_sub, []).append(meeting)
    per_owner = sorted(
        (OwnerTotals(owner, len(ms), sum(_hours(m) for m in ms)) for owner, ms in owners.items()),
        key=lambda o: (-o.hours, o.owner),
    )

    zone = ZoneInfo(timezone)
    return WeeklyReport(
        week=week,
        timezone=timezone,
        current=_totals(week, current),
        previous=_totals(before, previous),
        longest=[
            LongMeeting(m.title, m.starts_at.astimezone(zone), _hours(m), m.attendee_count)
            for m in longest
        ],
        per_owner=per_owner,
    )


# --- csv --------------------------------------------------------------------


def _num(value: float) -> str:
    return f"{value:.2f}"


def _signed(value: float, *, integer: bool = False) -> str:
    text = str(int(value)) if integer else _num(value)
    return text if value < 0 else f"+{text}"


def render_csv(report: WeeklyReport) -> bytes:
    """A CSV in sections: summary, the five longest meetings, totals per account.

    No timestamp of when it was built: the same data gives the same bytes.
    """
    monday = parse_week(report.week)
    buffer = io.StringIO()
    out = csv.writer(buffer, lineterminator="\n")
    cur, prev = report.current, report.previous

    out.writerow(["Spry weekly meetings report"])
    out.writerow(["week", report.week])
    out.writerow(["from", monday.isoformat()])
    out.writerow(["to", (monday + timedelta(days=6)).isoformat()])
    out.writerow(["timezone", report.timezone])
    out.writerow([])

    out.writerow(["summary", cur.week, prev.week, "change"])
    meetings_change = _signed(cur.meetings - prev.meetings, integer=True)
    out.writerow(["meetings", cur.meetings, prev.meetings, meetings_change])
    out.writerow(["hours", _num(cur.hours), _num(prev.hours), _signed(cur.hours - prev.hours)])
    out.writerow([])

    out.writerow(["longest meetings"])
    out.writerow(["rank", "title", "starts at", "duration (h)", "participants"])
    for rank, m in enumerate(report.longest, start=1):
        starts = m.starts_at.strftime("%Y-%m-%d %H:%M")
        out.writerow([rank, m.title, starts, _num(m.hours), m.participants])
    out.writerow([])

    out.writerow(["per account"])
    out.writerow(["account", "meetings", "hours"])
    for o in report.per_owner:
        out.writerow([o.owner, o.meetings, _num(o.hours)])

    return buffer.getvalue().encode("utf-8")


# --- entry point ------------------------------------------------------------


async def _build(week: str) -> bytes:
    settings = get_settings()
    # Its own engine with no pool: called from asyncio.run(), once per report.
    engine = create_async_engine(settings.database_url, poolclass=NullPool)
    try:
        async with async_sessionmaker(engine, expire_on_commit=False)() as session:
            report = await collect(session, week, settings.report_timezone)
    finally:
        await engine.dispose()
    return render_csv(report)


def build_weekly_report(week: str) -> bytes:
    """Query the meetings of one ISO week (e.g. "2026-W40") and return the CSV."""
    parse_week(week)
    return asyncio.run(_build(week))


if __name__ == "__main__":
    tz = get_settings().report_timezone
    week = sys.argv[1] if len(sys.argv) > 1 else previous_week(timezone=tz)
    sys.stdout.write(build_weekly_report(week).decode())
