"""Add revocable QR passes and one-time attendance records.

Revision ID: 0004_event_attendance_qr
Revises: 0003_events_registration
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0004_event_attendance_qr"
down_revision = "0003_events_registration"
branch_labels = None
depends_on = None


def upgrade() -> None:
    uuid_type = postgresql.UUID(as_uuid=True)
    op.create_table(
        "event_tickets",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("registration_id", sa.Integer(), nullable=False),
        sa.Column("token_hash", sa.String(length=64), nullable=False),
        sa.Column("issued_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True)),
        sa.Column("consumed_at", sa.DateTime(timezone=True)),
        sa.ForeignKeyConstraint(
            ["registration_id"],
            ["event_registrations.id"],
            name="fk_event_tickets_registration_id_event_registrations",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_event_tickets"),
        sa.UniqueConstraint("registration_id", name="uq_event_tickets_registration"),
        sa.UniqueConstraint("token_hash", name="uq_event_tickets_token_hash"),
    )
    op.create_table(
        "event_attendance",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("registration_id", sa.Integer(), nullable=False),
        sa.Column("event_id", sa.Integer(), nullable=False),
        sa.Column("student_id", uuid_type, nullable=False),
        sa.Column("checked_in_by", uuid_type, nullable=False),
        sa.Column("checked_in_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column(
            "validation_method",
            sa.String(length=24),
            server_default="QR",
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["checked_in_by"],
            ["users.id"],
            name="fk_event_attendance_checked_in_by_users",
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(
            ["event_id"],
            ["events.id"],
            name="fk_event_attendance_event_id_events",
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(
            ["registration_id"],
            ["event_registrations.id"],
            name="fk_event_attendance_registration_id_event_registrations",
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(
            ["student_id"],
            ["users.id"],
            name="fk_event_attendance_student_id_users",
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_event_attendance"),
        sa.UniqueConstraint(
            "registration_id",
            name="uq_event_attendance_registration",
        ),
    )
    op.create_index(
        "ix_event_attendance_event_checked_in",
        "event_attendance",
        ["event_id", "checked_in_at"],
    )
    op.create_index(
        "ix_event_attendance_student_checked_in",
        "event_attendance",
        ["student_id", "checked_in_at"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_event_attendance_student_checked_in",
        table_name="event_attendance",
    )
    op.drop_index(
        "ix_event_attendance_event_checked_in",
        table_name="event_attendance",
    )
    op.drop_table("event_attendance")
    op.drop_table("event_tickets")
