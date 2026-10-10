"""Add event eligibility and persistent announcements.

Revision ID: 0005_announcements_eligibility
Revises: 0004_event_attendance_qr
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0005_announcements_eligibility"
down_revision = "0004_event_attendance_qr"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("events", sa.Column("eligibility", sa.String(length=500)))
    op.add_column("notifications", sa.Column("target_path", sa.String(length=255)))
    op.create_table(
        "announcements",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("club_id", sa.Integer(), nullable=True),
        sa.Column("created_by", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("title", sa.String(length=180), nullable=False),
        sa.Column("body", sa.Text(), nullable=False),
        sa.Column(
            "status",
            sa.Enum(
                "DRAFT",
                "PUBLISHED",
                "CANCELLED",
                name="announcementstatus",
                native_enum=False,
                length=16,
            ),
            server_default="DRAFT",
            nullable=False,
        ),
        sa.Column("published_at", sa.DateTime(timezone=True)),
        sa.Column("expires_at", sa.DateTime(timezone=True)),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.CheckConstraint(
            "status IN ('DRAFT', 'PUBLISHED', 'CANCELLED')",
            name="ck_announcements_valid_status",
        ),
        sa.ForeignKeyConstraint(
            ["club_id"],
            ["clubs.id"],
            name="fk_announcements_club_id_clubs",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["created_by"],
            ["users.id"],
            name="fk_announcements_created_by_users",
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_announcements"),
    )
    op.create_index(
        "ix_announcements_club_status_published",
        "announcements",
        ["club_id", "status", "published_at"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_announcements_club_status_published",
        table_name="announcements",
    )
    op.drop_table("announcements")
    op.drop_column("notifications", "target_path")
    op.drop_column("events", "eligibility")
