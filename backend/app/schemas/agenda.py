"""A meeting's agenda, and the shape the agenda parser (app/ai/agenda.py) must return.

ParsedAgenda is the parser's contract with the model: the JSON schema of its one
tool, and what every answer is validated against before it leaves the function.
AgendaWrite is what the normal Save sends to the API; it may carry the parser's
suggestion along, so the difference between the two can be measured later.
"""

from datetime import date, datetime
from typing import Annotated

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    StringConstraints,
    field_serializer,
    field_validator,
)

from app.schemas.common import utc_z

Text = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=500)]
Name = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=200)]


class AgendaItem(BaseModel):
    topic: str = Field(min_length=1)
    owner: str | None = None  # a name or an email, exactly as written
    minutes: int | None = Field(default=None, ge=1, le=480)


class ActionItem(BaseModel):
    task: str = Field(min_length=1)
    owner: str | None = None
    due: date | None = None


class ParsedAgenda(BaseModel):
    title: str | None = None
    starts_at: str | None = None  # ISO 8601 with the user's offset, if the text says when
    duration_minutes: int | None = Field(default=None, ge=1, le=600)
    items: list[AgendaItem]
    action_items: list[ActionItem] = []
    language: str  # "uk", "en", ...

    @field_validator("starts_at")
    @classmethod
    def _iso_with_offset(cls, value: str | None) -> str | None:
        # A time without an offset means nothing once it reaches the browser.
        if value is not None and datetime.fromisoformat(value).tzinfo is None:
            raise ValueError("starts_at needs a UTC offset, e.g. 2026-10-19T10:00:00+03:00")
        return value


# --- what the API stores -------------------------------------------------------


class AgendaItemIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    topic: Text
    owner: Name | None = None
    minutes: int | None = Field(default=None, ge=1, le=480)


class ActionItemIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    task: Text
    owner: Name | None = None
    due: date | None = None


class AiSuggestion(BaseModel):
    """What the parser proposed, exactly as it returned it, and who proposed it."""

    agenda: ParsedAgenda
    model: Annotated[str, StringConstraints(min_length=1, max_length=100)]
    prompt_version: Annotated[str, StringConstraints(min_length=1, max_length=40)]


class AgendaWrite(BaseModel):
    model_config = ConfigDict(extra="forbid")

    items: Annotated[list[AgendaItemIn], Field(max_length=50)]
    action_items: Annotated[list[ActionItemIn], Field(max_length=50)] = []
    # Present when the form started from "Paste an agenda"; null when typed by hand.
    ai_suggestion: AiSuggestion | None = None


class AgendaRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    meeting_id: int
    items: list[AgendaItemIn]
    action_items: list[ActionItemIn]
    ai_model: str | None
    ai_prompt_version: str | None
    updated_at: datetime

    @field_serializer("updated_at")
    def _as_utc_z(self, value: datetime) -> str:
        return utc_z(value)
