"""Business logic and queries. No HTTP types here."""

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Attachment, Meeting
from app.schemas import MeetingCreate, MeetingUpdate


class InvalidMeeting(ValueError):
    """The merged meeting breaks a rule (e.g. it would end before it starts)."""


def _attachment_count():
    return (
        select(func.count(Attachment.id))
        .where(Attachment.meeting_id == Meeting.id)
        .correlate(Meeting)
        .scalar_subquery()
    )


async def list_meetings(session: AsyncSession) -> list[tuple[Meeting, int]]:
    result = await session.execute(
        select(Meeting, _attachment_count()).order_by(Meeting.starts_at, Meeting.id)
    )
    return [(meeting, count) for meeting, count in result.all()]


async def get_meeting(session: AsyncSession, meeting_id: int) -> Meeting | None:
    return await session.get(Meeting, meeting_id)


async def count_attachments(session: AsyncSession, meeting_id: int) -> int:
    count = await session.scalar(
        select(func.count(Attachment.id)).where(Attachment.meeting_id == meeting_id)
    )
    return count or 0


async def create_meeting(session: AsyncSession, payload: MeetingCreate) -> Meeting:
    meeting = Meeting(**payload.model_dump())
    session.add(meeting)
    await session.flush()
    await session.refresh(meeting)
    return meeting


async def update_meeting(
    session: AsyncSession, meeting: Meeting, payload: MeetingUpdate
) -> Meeting:
    changes = payload.model_dump(exclude_unset=True)
    starts_at = changes.get("starts_at", meeting.starts_at)
    ends_at = changes.get("ends_at", meeting.ends_at)
    if ends_at <= starts_at:
        raise InvalidMeeting("ends_at must be after starts_at")
    for field, value in changes.items():
        setattr(meeting, field, value)
    await session.flush()
    await session.refresh(meeting)
    return meeting
