from datetime import datetime
from typing import Any

from sqlalchemy import DateTime, ForeignKey, String, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


class Agenda(Base):
    """One agenda per meeting. Saving again replaces it."""

    __tablename__ = "agendas"

    meeting_id: Mapped[int] = mapped_column(
        ForeignKey("meetings.id", ondelete="CASCADE"), primary_key=True
    )
    # [{topic, owner, minutes}] and [{task, owner, due}], validated by AgendaWrite.
    items: Mapped[list[dict[str, Any]]] = mapped_column(JSONB, nullable=False)
    action_items: Mapped[list[dict[str, Any]]] = mapped_column(
        JSONB, nullable=False, server_default="[]"
    )
    # What the agenda parser proposed before the user corrected it (null when
    # typed by hand). Suggested vs saved is the parser's quality signal.
    ai_suggestion: Mapped[dict[str, Any] | None] = mapped_column(JSONB, nullable=True)
    ai_model: Mapped[str | None] = mapped_column(String(100), nullable=True)
    ai_prompt_version: Mapped[str | None] = mapped_column(String(40), nullable=True)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
