"""create meetings table

Revision ID: 0001
Revises:
Create Date: 2026-10-01

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0001"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "meetings",
        sa.Column("id", sa.Integer(), sa.Identity(), nullable=False),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("starts_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ends_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("attendee_count", sa.Integer(), nullable=False),
        sa.PrimaryKeyConstraint("id", name="pk_meetings"),
        sa.CheckConstraint("ends_at > starts_at", name="ck_meetings_ends_after_starts"),
        sa.CheckConstraint("attendee_count BETWEEN 1 AND 1000", name="ck_meetings_attendee_count"),
    )
    op.create_index("ix_meetings_starts_at", "meetings", ["starts_at"])


def downgrade() -> None:
    op.drop_index("ix_meetings_starts_at", table_name="meetings")
    op.drop_table("meetings")
