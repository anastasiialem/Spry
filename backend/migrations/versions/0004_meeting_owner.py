"""meetings belong to a user (owner_sub)

Revision ID: 0004
Revises: 0003
Create Date: 2026-10-08

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0004"
down_revision: str | None = "0003"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Rows from before sign-in belong to nobody; "unclaimed" matches no Cognito
    # sub, so they simply stop being visible.
    op.add_column("meetings", sa.Column("owner_sub", sa.String(length=64), nullable=True))
    op.execute("UPDATE meetings SET owner_sub = 'unclaimed' WHERE owner_sub IS NULL")
    op.alter_column("meetings", "owner_sub", nullable=False)
    op.create_index("ix_meetings_owner_sub", "meetings", ["owner_sub"])


def downgrade() -> None:
    op.drop_index("ix_meetings_owner_sub", table_name="meetings")
    op.drop_column("meetings", "owner_sub")
