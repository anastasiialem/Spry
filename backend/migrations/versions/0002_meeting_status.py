"""add meetings.status

Revision ID: 0002
Revises: 0001
Create Date: 2026-10-01

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0002"
down_revision: str | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # server_default fills the rows that already exist, so NOT NULL is safe.
    op.add_column(
        "meetings",
        sa.Column("status", sa.String(length=20), server_default="not_started", nullable=False),
    )
    op.create_check_constraint(
        "ck_meetings_status", "meetings", "status IN ('not_started', 'in_progress', 'done')"
    )


def downgrade() -> None:
    op.drop_constraint("ck_meetings_status", "meetings", type_="check")
    op.drop_column("meetings", "status")
