from datetime import datetime

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    Identity,
    Integer,
    LargeBinary,
    String,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base

MAX_ATTACHMENT_BYTES = 4 * 1024 * 1024


class Attachment(Base):
    """A file attached to a meeting. The bytes live in `data` (see docs/decisions/0002)."""

    __tablename__ = "attachments"
    __table_args__ = (
        CheckConstraint(f"size BETWEEN 1 AND {MAX_ATTACHMENT_BYTES}", name="ck_attachments_size"),
    )

    id: Mapped[int] = mapped_column(Integer, Identity(), primary_key=True)
    meeting_id: Mapped[int] = mapped_column(
        ForeignKey("meetings.id", ondelete="CASCADE"), nullable=False, index=True
    )
    filename: Mapped[str] = mapped_column(String(255), nullable=False)
    content_type: Mapped[str] = mapped_column(String(127), nullable=False)
    size: Mapped[int] = mapped_column(Integer, nullable=False)
    # deferred: list queries never pull file bytes; only a download does.
    data: Mapped[bytes] = mapped_column(LargeBinary, nullable=False, deferred=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
