"""agendas: one per meeting, with the parser's suggestion next to it

Revision ID: 0005
Revises: 0004
Create Date: 2026-10-18

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0005"
down_revision: str | None = "0004"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "agendas",
        sa.Column(
            "meeting_id",
            sa.Integer(),
            sa.ForeignKey("meetings.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("items", postgresql.JSONB(), nullable=False),
        sa.Column("action_items", postgresql.JSONB(), nullable=False, server_default="[]"),
        sa.Column("ai_suggestion", postgresql.JSONB(), nullable=True),
        sa.Column("ai_model", sa.String(length=100), nullable=True),
        sa.Column("ai_prompt_version", sa.String(length=40), nullable=True),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
    )


def downgrade() -> None:
    op.drop_table("agendas")
