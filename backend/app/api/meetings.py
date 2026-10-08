"""HTTP layer: parse and validate input, call the service, choose the status code."""

from typing import Annotated

from fastapi import APIRouter, HTTPException, Query, Request, status

from app.auth import CurrentUser
from app.db import SessionDep
from app.models import Meeting
from app.models.attachment import MAX_ATTACHMENT_BYTES
from app.schemas import AttachmentRead, MeetingCreate, MeetingRead, MeetingUpdate
from app.services import attachments as attachments_service
from app.services import meetings as meetings_service

router = APIRouter(prefix="/api/meetings", tags=["meetings"])


def _read(meeting: Meeting, attachment_count: int) -> MeetingRead:
    return MeetingRead.model_validate(meeting).model_copy(
        update={"attachment_count": attachment_count}
    )


async def _get_or_404(session: SessionDep, user: str, meeting_id: int) -> Meeting:
    meeting = await meetings_service.get_meeting(session, user, meeting_id)
    if meeting is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Meeting not found")
    return meeting


@router.get("", response_model=list[MeetingRead], summary="List meetings by start time")
async def list_meetings(session: SessionDep, user: CurrentUser) -> list[MeetingRead]:
    rows = await meetings_service.list_meetings(session, user)
    return [_read(meeting, count) for meeting, count in rows]


@router.post(
    "",
    response_model=MeetingRead,
    status_code=status.HTTP_201_CREATED,
    summary="Create a meeting",
)
async def create_meeting(
    payload: MeetingCreate, session: SessionDep, user: CurrentUser
) -> MeetingRead:
    meeting = await meetings_service.create_meeting(session, user, payload)
    return _read(meeting, 0)


@router.patch("/{meeting_id}", response_model=MeetingRead, summary="Edit a meeting")
async def update_meeting(
    meeting_id: int, payload: MeetingUpdate, session: SessionDep, user: CurrentUser
) -> MeetingRead:
    meeting = await _get_or_404(session, user, meeting_id)
    try:
        meeting = await meetings_service.update_meeting(session, meeting, payload)
    except meetings_service.InvalidMeeting as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    count = await meetings_service.count_attachments(session, meeting.id)
    return _read(meeting, count)


@router.get(
    "/{meeting_id}/attachments",
    response_model=list[AttachmentRead],
    summary="List a meeting's files",
)
async def list_attachments(
    meeting_id: int, session: SessionDep, user: CurrentUser
) -> list[AttachmentRead]:
    await _get_or_404(session, user, meeting_id)
    attachments = await attachments_service.list_attachments(session, meeting_id)
    return [AttachmentRead.model_validate(a) for a in attachments]


@router.post(
    "/{meeting_id}/attachments",
    response_model=AttachmentRead,
    status_code=status.HTTP_201_CREATED,
    summary="Upload a file (raw request body)",
)
async def upload_attachment(
    meeting_id: int,
    request: Request,
    session: SessionDep,
    user: CurrentUser,
    filename: Annotated[str, Query(min_length=1, max_length=255)],
) -> AttachmentRead:
    await _get_or_404(session, user, meeting_id)

    too_large = HTTPException(
        status_code=413,
        detail=f"File is larger than {MAX_ATTACHMENT_BYTES // (1024 * 1024)} MB",
    )
    declared = request.headers.get("content-length")
    if declared and declared.isdigit() and int(declared) > MAX_ATTACHMENT_BYTES:
        raise too_large
    data = await request.body()
    if len(data) > MAX_ATTACHMENT_BYTES:
        raise too_large
    if not data:
        raise HTTPException(status_code=422, detail="Empty file")

    name = attachments_service.clean_filename(filename)
    if not name:
        raise HTTPException(status_code=422, detail="Invalid filename")

    attachment = await attachments_service.create_attachment(
        session,
        meeting_id,
        filename=name,
        content_type=request.headers.get("content-type"),
        data=data,
    )
    return AttachmentRead.model_validate(attachment)
