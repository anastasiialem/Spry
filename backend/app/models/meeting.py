from datetime import datetime

from sqlalchemy import CheckConstraint, DateTime, Identity, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base

MEETING_STATUSES = ("not_started", "in_progress", "done")


class Meeting(Base):
    __tablename__ = "meetings"
    __table_args__ = (
        CheckConstraint("ends_at > starts_at", name="ck_meetings_ends_after_starts"),
        CheckConstraint("attendee_count BETWEEN 1 AND 1000", name="ck_meetings_attendee_count"),
        CheckConstraint(
            "status IN ('not_started', 'in_progress', 'done')", name="ck_meetings_status"
        ),
    )

    id: Mapped[int] = mapped_column(Integer, Identity(), primary_key=True)
    # Cognito "sub" of the user who created it. Every query filters on it.
    owner_sub: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    starts_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
    ends_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    attendee_count: Mapped[int] = mapped_column(Integer, nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False, server_default="not_started")
