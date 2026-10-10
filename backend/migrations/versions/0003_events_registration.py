"""Add persistent events and registrations.

Revision ID: 0003_events_registration
Revises: 0002_membership_integrity
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0003_events_registration"
down_revision = "0002_membership_integrity"
branch_labels = None
depends_on = None


def upgrade() -> None:
    uuid_type = postgresql.UUID(as_uuid=True)
    event_status = sa.Enum(
        "DRAFT",
        "PUBLISHED",
        "CANCELLED",
        "COMPLETED",
        name="eventstatus",
        native_enum=False,
        length=16,
    )
    registration_status = sa.Enum(
        "REGISTERED",
        "CANCELLED",
        name="eventregistrationstatus",
        native_enum=False,
        length=16,
    )
    op.create_table(
        "events",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("club_id", sa.Integer(), nullable=False),
        sa.Column("title", sa.String(length=180), nullable=False),
        sa.Column("description", sa.Text()),
        sa.Column("category", sa.String(length=80)),
        sa.Column("poster_url", sa.String(length=2048)),
        sa.Column("start_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("end_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("registration_opens_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("registration_closes_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("venue", sa.String(length=240), nullable=False),
        sa.Column("latitude", sa.Float()),
        sa.Column("longitude", sa.Float()),
        sa.Column("capacity", sa.Integer(), nullable=False),
        sa.Column(
            "status",
            event_status,
            server_default="DRAFT",
            nullable=False,
        ),
        sa.Column("created_by", uuid_type, nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint(
            "status IN ('DRAFT', 'PUBLISHED', 'CANCELLED', 'COMPLETED')",
            name="ck_events_valid_status",
        ),
        sa.CheckConstraint("capacity > 0", name="ck_events_positive_capacity"),
        sa.CheckConstraint("end_at > start_at", name="ck_events_valid_event_range"),
        sa.CheckConstraint(
            "registration_closes_at >= registration_opens_at",
            name="ck_events_valid_registration_range",
        ),
        sa.CheckConstraint(
            "registration_closes_at <= start_at",
            name="ck_events_registration_closes_before_event",
        ),
        sa.CheckConstraint(
            "(latitude IS NULL AND longitude IS NULL) OR "
            "(latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180)",
            name="ck_events_valid_coordinates",
        ),
        sa.ForeignKeyConstraint(
            ["club_id"],
            ["clubs.id"],
            name="fk_events_club_id_clubs",
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(
            ["created_by"],
            ["users.id"],
            name="fk_events_created_by_users",
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_events"),
    )
    op.create_index("ix_events_status_start_at", "events", ["status", "start_at"])
    op.create_index(
        "ix_events_club_status_start_at",
        "events",
        ["club_id", "status", "start_at"],
    )
    op.create_table(
        "event_registrations",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("event_id", sa.Integer(), nullable=False),
        sa.Column("student_id", uuid_type, nullable=False),
        sa.Column(
            "status",
            registration_status,
            server_default="REGISTERED",
            nullable=False,
        ),
        sa.Column("registered_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("cancelled_at", sa.DateTime(timezone=True)),
        sa.CheckConstraint(
            "status IN ('REGISTERED', 'CANCELLED')",
            name="ck_event_registrations_valid_registration_status",
        ),
        sa.ForeignKeyConstraint(
            ["event_id"],
            ["events.id"],
            name="fk_event_registrations_event_id_events",
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(
            ["student_id"],
            ["users.id"],
            name="fk_event_registrations_student_id_users",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_event_registrations"),
        sa.UniqueConstraint(
            "event_id",
            "student_id",
            name="uq_event_registrations_event_student",
        ),
    )
    op.create_index(
        "ix_event_registrations_student_status",
        "event_registrations",
        ["student_id", "status"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_event_registrations_student_status",
        table_name="event_registrations",
    )
    op.drop_table("event_registrations")
    op.drop_index("ix_events_club_status_start_at", table_name="events")
    op.drop_index("ix_events_status_start_at", table_name="events")
    op.drop_table("events")
