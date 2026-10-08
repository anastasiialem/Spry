"""Attachment storage. The bytes live in Postgres; see docs/decisions/0002."""

from pathlib import PurePosixPath, PureWindowsPath

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import undefer

from app.models import Attachment, Meeting

DEFAULT_CONTENT_TYPE = "application/octet-stream"


def clean_filename(raw: str) -> str:
    """Keep only the last path segment, so a name can never carry a path.

    "../../etc/passwd" -> "passwd", "C:\\x\\a.pdf" -> "a.pdf", ".." -> "" (rejected).
    """
    name = PureWindowsPath(PurePosixPath(raw).name).name.strip()
    if name in {".", ".."}:
        return ""
    return name[:255]


async def list_attachments(session: AsyncSession, meeting_id: int) -> list[Attachment]:
    result = await session.scalars(
        select(Attachment)
        .where(Attachment.meeting_id == meeting_id)
        .order_by(Attachment.created_at, Attachment.id)
    )
    return list(result)


async def create_attachment(
    session: AsyncSession,
    meeting_id: int,
    *,
    filename: str,
    content_type: str | None,
    data: bytes,
) -> Attachment:
    attachment = Attachment(
        meeting_id=meeting_id,
        filename=filename,
        content_type=(content_type or DEFAULT_CONTENT_TYPE)[:127],
        size=len(data),
        data=data,
    )
    session.add(attachment)
    await session.flush()
    await session.refresh(attachment, attribute_names=["id", "created_at"])
    return attachment


async def get_attachment(
    session: AsyncSession, owner: str, attachment_id: int, *, with_data: bool = False
) -> Attachment | None:
    """Only attachments of the owner's own meetings; anything else is "not found"."""
    query = (
        select(Attachment)
        .join(Meeting, Meeting.id == Attachment.meeting_id)
        .where(Attachment.id == attachment_id, Meeting.owner_sub == owner)
    )
    if with_data:
        query = query.options(undefer(Attachment.data))
    return await session.scalar(query)


async def delete_attachment(session: AsyncSession, attachment: Attachment) -> None:
    await session.delete(attachment)
    await session.flush()
