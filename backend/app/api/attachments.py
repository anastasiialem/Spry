"""Download and delete a single attachment by its own id."""

from urllib.parse import quote

from fastapi import APIRouter, HTTPException, Response, status

from app.db import SessionDep
from app.services import attachments as attachments_service

router = APIRouter(prefix="/api/attachments", tags=["attachments"])


def _not_found() -> HTTPException:
    return HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Attachment not found")


@router.get("/{attachment_id}", summary="Download a file", response_class=Response)
async def download_attachment(attachment_id: int, session: SessionDep) -> Response:
    attachment = await attachments_service.get_attachment(session, attachment_id, with_data=True)
    if attachment is None:
        raise _not_found()
    return Response(
        content=attachment.data,
        media_type=attachment.content_type,
        headers={
            # filename* handles non-ASCII names (e.g. Cyrillic) correctly.
            "Content-Disposition": f"attachment; filename*=UTF-8''{quote(attachment.filename)}",
            "X-Content-Type-Options": "nosniff",
        },
    )


@router.delete("/{attachment_id}", status_code=status.HTTP_204_NO_CONTENT, summary="Delete a file")
async def delete_attachment(attachment_id: int, session: SessionDep) -> Response:
    attachment = await attachments_service.get_attachment(session, attachment_id)
    if attachment is None:
        raise _not_found()
    await attachments_service.delete_attachment(session, attachment)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
