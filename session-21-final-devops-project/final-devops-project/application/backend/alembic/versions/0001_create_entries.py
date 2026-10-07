"""create entries table

Revision ID: 0001
Revises:
Create Date: 2026-10-07
"""
import sqlalchemy as sa
from alembic import op

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "entries",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("customer", sa.String(80), nullable=False),
        sa.Column("amount", sa.Numeric(10, 2), nullable=False),
        sa.Column("type", sa.String(10), nullable=False),
        sa.Column("note", sa.String(200), nullable=False, server_default=""),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.CheckConstraint("type IN ('udhar', 'payment', 'sale')", name="ck_entries_type"),
        sa.CheckConstraint("amount > 0", name="ck_entries_amount_positive"),
    )
    op.create_index("ix_entries_customer", "entries", ["customer"])


def downgrade():
    op.drop_index("ix_entries_customer", table_name="entries")
    op.drop_table("entries")
