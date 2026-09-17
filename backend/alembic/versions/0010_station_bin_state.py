"""stations.bin_full + stations.last_error — bin state surfaced to admins.

A full bin and/or an error condition reported by the station over MQTT, used
to drive the admin alert banner so the operator knows when a bin is full or
faulted.

Revision ID: 0010_station_bin_state
Revises: 0009_station_mechanism
Create Date: 2026-08-29
"""
from alembic import op
import sqlalchemy as sa


revision = "0010_station_bin_state"
down_revision = "0009_station_mechanism"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "stations",
        sa.Column("bin_full", sa.Boolean(), nullable=False, server_default=sa.false()),
    )
    op.add_column(
        "stations",
        sa.Column("last_error", sa.String(255), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("stations", "last_error")
    op.drop_column("stations", "bin_full")
