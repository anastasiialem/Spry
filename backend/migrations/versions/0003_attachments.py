"""create attachments table

Revision ID: 0003
Revises: 0002
Create Date: 2026-10-01

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0003"
down_revision: str | None = "0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "attachments",
        sa.Column("id", sa.Integer(), sa.Identity(), nullable=False),
        sa.Column("meeting_id", sa.Integer(), nullable=False),
        sa.Column("filename", sa.String(length=255), nullable=False),
        sa.Column("content_type", sa.String(length=127), nullable=False),
        sa.Column("size", sa.Integer(), nullable=False),
        sa.Column("data", sa.LargeBinary(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id", name="pk_attachments"),
        sa.ForeignKeyConstraint(
            ["meeting_id"], ["meetings.id"], name="fk_attachments_meeting", ondelete="CASCADE"
        ),
        sa.CheckConstraint("size BETWEEN 1 AND 4194304", name="ck_attachments_size"),
    )
    op.create_index("ix_attachments_meeting_id", "attachments", ["meeting_id"])


def downgrade() -> None:
    op.drop_index("ix_attachments_meeting_id", table_name="attachments")
    op.drop_table("attachments")
