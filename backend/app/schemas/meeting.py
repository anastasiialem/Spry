"""The API contract from PROJECT.md section 4, in code."""

from datetime import datetime
from typing import Annotated, Literal, Self

from pydantic import (
    AwareDatetime,
    BaseModel,
    ConfigDict,
    Field,
    StringConstraints,
    field_serializer,
    model_validator,
)

from app.schemas.common import utc_z

Title = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=200)]
AttendeeCount = Annotated[int, Field(ge=1, le=1000)]
MeetingStatus = Literal["not_started", "in_progress", "done"]


class MeetingCreate(BaseModel):
    title: Title
    # AwareDatetime rejects "2026-10-05T09:00:00" (no timezone) with a 422.
    starts_at: AwareDatetime
    ends_at: AwareDatetime
    attendee_count: AttendeeCount
    status: MeetingStatus = "not_started"

    @model_validator(mode="after")
    def _ends_after_start(self) -> Self:
        if self.ends_at <= self.starts_at:
            raise ValueError("ends_at must be after starts_at")
        return self


class MeetingUpdate(BaseModel):
    """PATCH body: any non-empty subset of the fields. The start/end order is checked in
    the service, after merging with the stored values."""

    model_config = ConfigDict(extra="forbid")

    title: Title | None = None
    starts_at: AwareDatetime | None = None
    ends_at: AwareDatetime | None = None
    attendee_count: AttendeeCount | None = None
    status: MeetingStatus | None = None

    @model_validator(mode="after")
    def _non_empty_no_nulls(self) -> Self:
        if not self.model_fields_set:
            raise ValueError("send at least one field to change")
        nulls = [name for name in self.model_fields_set if getattr(self, name) is None]
        if nulls:
            raise ValueError(f"fields cannot be null: {', '.join(sorted(nulls))}")
        return self


class MeetingRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    title: str
    starts_at: datetime
    ends_at: datetime
    attendee_count: int
    status: MeetingStatus
    attachment_count: int = 0

    @field_serializer("starts_at", "ends_at")
    def _as_utc_z(self, value: datetime) -> str:
        return utc_z(value)
