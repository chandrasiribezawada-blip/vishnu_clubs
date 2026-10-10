"""Create identity, clubs and persistent membership workflow tables.

Revision ID: 0001_initial_core
Revises:
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0001_initial_core"
down_revision = None
branch_labels = None
depends_on = None

role_enum = sa.Enum(
    "STUDENT", "CLUB_MEMBER_COORDINATOR", "CLUB_ADMIN", name="userrole", native_enum=False
)
request_status = sa.Enum(
    "PENDING", "APPROVED", "REJECTED", name="joinrequeststatus", native_enum=False
)
uuid_type = postgresql.UUID(as_uuid=True)


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", uuid_type, nullable=False),
        sa.Column("email", sa.String(320), nullable=False),
        sa.Column("full_name", sa.String(160), nullable=False),
        sa.Column("password_hash", sa.String(512), nullable=False),
        sa.Column("role", role_enum, nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.PrimaryKeyConstraint("id", name="pk_users"),
        sa.UniqueConstraint("email", name="uq_users_email"),
    )
    op.create_index("ix_users_email", "users", ["email"], unique=False)
    op.create_table(
        "student_profiles",
        sa.Column("user_id", uuid_type, nullable=False),
        sa.Column("registration_number", sa.String(64), nullable=False),
        sa.Column("department", sa.String(120), nullable=False),
        sa.Column("year", sa.String(32), nullable=False),
        sa.Column("section", sa.String(32)),
        sa.Column("phone_number", sa.String(32), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], name="fk_student_profiles_user_id_users", ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("user_id", name="pk_student_profiles"),
        sa.UniqueConstraint("registration_number", name="uq_student_profiles_registration_number"),
    )
    op.create_table(
        "clubs",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("name", sa.String(200), nullable=False),
        sa.Column("category", sa.String(100)),
        sa.Column("description", sa.Text()),
        sa.Column("objectives", sa.Text()),
        sa.Column("contact_email", sa.String(320)),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.PrimaryKeyConstraint("id", name="pk_clubs"),
        sa.UniqueConstraint("name", name="uq_clubs_name"),
    )
    op.create_table(
        "club_coordinators",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("user_id", uuid_type, nullable=False),
        sa.Column("club_id", sa.Integer(), nullable=False),
        sa.Column("assigned_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True)),
        sa.ForeignKeyConstraint(["club_id"], ["clubs.id"], name="fk_club_coordinators_club_id_clubs", ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], name="fk_club_coordinators_user_id_users", ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id", name="pk_club_coordinators"),
    )
    op.create_index(
        "uq_club_coordinators_active_assignment",
        "club_coordinators",
        ["user_id", "club_id"],
        unique=True,
        postgresql_where=sa.text("revoked_at IS NULL"),
        sqlite_where=sa.text("revoked_at IS NULL"),
    )
    op.create_table(
        "club_join_requests",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("student_id", uuid_type, nullable=False),
        sa.Column("club_id", sa.Integer(), nullable=False),
        sa.Column("reason", sa.Text(), nullable=False),
        sa.Column("skills", sa.Text(), nullable=False),
        sa.Column("experience", sa.Text()),
        sa.Column("status", request_status, nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("decided_at", sa.DateTime(timezone=True)),
        sa.CheckConstraint("status IN ('PENDING', 'APPROVED', 'REJECTED')", name="ck_club_join_requests_valid_status"),
        sa.ForeignKeyConstraint(["club_id"], ["clubs.id"], name="fk_club_join_requests_club_id_clubs", ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["student_id"], ["users.id"], name="fk_club_join_requests_student_id_users", ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id", name="pk_club_join_requests"),
    )
    op.create_index(
        "uq_club_join_requests_pending_student_club",
        "club_join_requests",
        ["student_id", "club_id"],
        unique=True,
        postgresql_where=sa.text("status = 'PENDING'"),
        sqlite_where=sa.text("status = 'PENDING'"),
    )
    op.create_table(
        "join_request_decisions",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("request_id", sa.Integer(), nullable=False),
        sa.Column("decided_by", uuid_type, nullable=False),
        sa.Column("status", request_status, nullable=False),
        sa.Column("note", sa.Text()),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["decided_by"], ["users.id"], name="fk_join_request_decisions_decided_by_users"),
        sa.ForeignKeyConstraint(["request_id"], ["club_join_requests.id"], name="fk_join_request_decisions_request_id_club_join_requests", ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id", name="pk_join_request_decisions"),
    )
    op.create_index("ix_join_request_decisions_request_id", "join_request_decisions", ["request_id"])
    op.create_table(
        "club_memberships",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("student_id", uuid_type, nullable=False),
        sa.Column("club_id", sa.Integer(), nullable=False),
        sa.Column("join_request_id", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("ended_at", sa.DateTime(timezone=True)),
        sa.ForeignKeyConstraint(["club_id"], ["clubs.id"], name="fk_club_memberships_club_id_clubs", ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["join_request_id"], ["club_join_requests.id"], name="fk_club_memberships_join_request_id_club_join_requests"),
        sa.ForeignKeyConstraint(["student_id"], ["users.id"], name="fk_club_memberships_student_id_users", ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id", name="pk_club_memberships"),
        sa.UniqueConstraint("join_request_id", name="uq_club_memberships_join_request_id"),
    )
    op.create_index(
        "uq_club_memberships_active_student_club",
        "club_memberships",
        ["student_id", "club_id"],
        unique=True,
        postgresql_where=sa.text("ended_at IS NULL"),
        sqlite_where=sa.text("ended_at IS NULL"),
    )
    op.create_table(
        "club_followers",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("student_id", uuid_type, nullable=False),
        sa.Column("club_id", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["club_id"], ["clubs.id"], name="fk_club_followers_club_id_clubs", ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["student_id"], ["users.id"], name="fk_club_followers_student_id_users", ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id", name="pk_club_followers"),
        sa.UniqueConstraint("student_id", "club_id", name="uq_club_followers_student_club"),
    )
    op.create_table(
        "refresh_sessions",
        sa.Column("id", uuid_type, nullable=False),
        sa.Column("user_id", uuid_type, nullable=False),
        sa.Column("refresh_token_digest", sa.String(64), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True)),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], name="fk_refresh_sessions_user_id_users", ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id", name="pk_refresh_sessions"),
    )
    op.create_index("ix_refresh_sessions_user_id", "refresh_sessions", ["user_id"])
    op.create_table(
        "notifications",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("recipient_id", uuid_type, nullable=False),
        sa.Column("title", sa.String(180), nullable=False),
        sa.Column("message", sa.Text(), nullable=False),
        sa.Column("read_at", sa.DateTime(timezone=True)),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["recipient_id"], ["users.id"], name="fk_notifications_recipient_id_users", ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id", name="pk_notifications"),
    )
    op.create_index("ix_notifications_recipient_id", "notifications", ["recipient_id"])
    op.create_table(
        "audit_logs",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("actor_id", uuid_type),
        sa.Column("action", sa.String(100), nullable=False),
        sa.Column("entity_type", sa.String(80), nullable=False),
        sa.Column("entity_id", sa.String(80), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["actor_id"], ["users.id"], name="fk_audit_logs_actor_id_users", ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id", name="pk_audit_logs"),
    )
    op.create_index("ix_audit_logs_action", "audit_logs", ["action"])


def downgrade() -> None:
    op.drop_index("ix_audit_logs_action", table_name="audit_logs")
    op.drop_table("audit_logs")
    op.drop_index("ix_notifications_recipient_id", table_name="notifications")
    op.drop_table("notifications")
    op.drop_index("ix_refresh_sessions_user_id", table_name="refresh_sessions")
    op.drop_table("refresh_sessions")
    op.drop_table("club_followers")
    op.drop_index("uq_club_memberships_active_student_club", table_name="club_memberships")
    op.drop_table("club_memberships")
    op.drop_index("ix_join_request_decisions_request_id", table_name="join_request_decisions")
    op.drop_table("join_request_decisions")
    op.drop_index("uq_club_join_requests_pending_student_club", table_name="club_join_requests")
    op.drop_table("club_join_requests")
    op.drop_index("uq_club_coordinators_active_assignment", table_name="club_coordinators")
    op.drop_table("club_coordinators")
    op.drop_table("clubs")
    op.drop_table("student_profiles")
    op.drop_index("ix_users_email", table_name="users")
    op.drop_table("users")
