"""HTTP layer: parse and validate input, call the service, choose the status code."""

from fastapi import APIRouter, status

from app.db import SessionDep
from app.schemas import MeetingCreate, MeetingRead
from app.services import meetings as meetings_service

router = APIRouter(prefix="/api/meetings", tags=["meetings"])


@router.get("", response_model=list[MeetingRead], summary="List meetings by start time")
async def list_meetings(session: SessionDep) -> list[MeetingRead]:
    meetings = await meetings_service.list_meetings(session)
    return [MeetingRead.model_validate(m) for m in meetings]


@router.post(
    "",
    response_model=MeetingRead,
    status_code=status.HTTP_201_CREATED,
    summary="Create a meeting",
)
async def create_meeting(payload: MeetingCreate, session: SessionDep) -> MeetingRead:
    meeting = await meetings_service.create_meeting(session, payload)
    return MeetingRead.model_validate(meeting)
