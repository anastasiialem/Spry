"""A meeting's agenda: read it, or replace it as a whole. No HTTP types here."""

from sqlalchemy import func
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Agenda
from app.schemas import AgendaWrite


async def get_agenda(session: AsyncSession, meeting_id: int) -> Agenda | None:
    return await session.get(Agenda, meeting_id)


async def save_agenda(session: AsyncSession, meeting_id: int, payload: AgendaWrite) -> Agenda:
    agenda = await session.get(Agenda, meeting_id) or Agenda(meeting_id=meeting_id)
    agenda.items = [item.model_dump(mode="json") for item in payload.items]
    agenda.action_items = [item.model_dump(mode="json") for item in payload.action_items]
    # Every save says where it started from: a typed agenda clears an older
    # suggestion, so the stored pair always describes the same edit.
    suggestion = payload.ai_suggestion
    agenda.ai_suggestion = suggestion.agenda.model_dump(mode="json") if suggestion else None
    agenda.ai_model = suggestion.model if suggestion else None
    agenda.ai_prompt_version = suggestion.prompt_version if suggestion else None
    agenda.updated_at = func.now()
    session.add(agenda)
    await session.flush()
    await session.refresh(agenda)
    return agenda
