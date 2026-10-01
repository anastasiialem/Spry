"""Business logic and queries. No HTTP types here."""

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Meeting
from app.schemas import MeetingCreate


async def list_meetings(session: AsyncSession) -> list[Meeting]:
    result = await session.scalars(select(Meeting).order_by(Meeting.starts_at, Meeting.id))
    return list(result)


async def create_meeting(session: AsyncSession, payload: MeetingCreate) -> Meeting:
    meeting = Meeting(**payload.model_dump())
    session.add(meeting)
    await session.flush()
    await session.refresh(meeting)
    return meeting
