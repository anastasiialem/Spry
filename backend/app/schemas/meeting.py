"""The API contract from PROJECT.md section 4, in code."""

from datetime import UTC, datetime
from typing import Annotated, Self

from pydantic import (
    AwareDatetime,
    BaseModel,
    ConfigDict,
    Field,
    StringConstraints,
    field_serializer,
    model_validator,
)

Title = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=200)]


class MeetingCreate(BaseModel):
    title: Title
    # AwareDatetime rejects "2026-10-05T09:00:00" (no timezone) with a 422.
    starts_at: AwareDatetime
    ends_at: AwareDatetime
    attendee_count: int = Field(ge=1, le=1000)

    @model_validator(mode="after")
    def _ends_after_start(self) -> Self:
        if self.ends_at <= self.starts_at:
            raise ValueError("ends_at must be after starts_at")
        return self


class MeetingRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    title: str
    starts_at: datetime
    ends_at: datetime
    attendee_count: int

    @field_serializer("starts_at", "ends_at")
    def _as_utc_z(self, value: datetime) -> str:
        """Always UTC with a trailing Z, e.g. 2026-10-05T09:00:00Z."""
        return value.astimezone(UTC).isoformat().replace("+00:00", "Z")
