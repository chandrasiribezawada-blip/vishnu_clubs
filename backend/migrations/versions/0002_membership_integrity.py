"""Strengthen membership request defaults and decision constraints.

Revision ID: 0002_membership_integrity
Revises: 0001_initial_core
"""

from alembic import op
import sqlalchemy as sa

revision = "0002_membership_integrity"
down_revision = "0001_initial_core"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.alter_column(
        "club_join_requests",
        "status",
        existing_type=sa.Enum(
            "PENDING",
            "APPROVED",
            "REJECTED",
            name="joinrequeststatus",
            native_enum=False,
        ),
        server_default="PENDING",
        existing_nullable=False,
    )
    op.create_check_constraint(
        "valid_decision_status",
        "join_request_decisions",
        "status IN ('APPROVED', 'REJECTED')",
    )
    op.create_unique_constraint(
        op.f("uq_join_request_decisions_request"),
        "join_request_decisions",
        ["request_id"],
    )


def downgrade() -> None:
    op.drop_constraint(
        "uq_join_request_decisions_request",
        "join_request_decisions",
        type_="unique",
    )
    op.drop_constraint(
        "ck_join_request_decisions_valid_decision_status",
        "join_request_decisions",
        type_="check",
    )
    op.alter_column(
        "club_join_requests",
        "status",
        existing_type=sa.Enum(
            "PENDING",
            "APPROVED",
            "REJECTED",
            name="joinrequeststatus",
            native_enum=False,
        ),
        server_default=None,
        existing_nullable=False,
    )
