from datetime import datetime

from pydantic import BaseModel, ConfigDict, field_serializer

from app.schemas.common import utc_z


class AttachmentRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    meeting_id: int
    filename: str
    content_type: str
    size: int
    created_at: datetime

    @field_serializer("created_at")
    def _as_utc_z(self, value: datetime) -> str:
        return utc_z(value)
