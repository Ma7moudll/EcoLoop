"""Challenge boolean columns: legacy INTEGER -> real BOOLEAN.

The original challenges table declared `completed` / `active` as Integer
(0/1) because the prototype ran on SQLite. On PostgreSQL a Boolean-typed
ORM column emits `IS TRUE` predicates, which fail against an integer column
(DatatypeMismatch). Convert the stored values properly.

SQLite keeps its dynamic typing: ALTER COLUMN is not supported there, so the
conversion is skipped (batch mode not needed — 0/1 ints behave as booleans).
"""
from alembic import op
import sqlalchemy as sa

revision = "0004_challenge_bools"
down_revision = "0003_hardening_auth_challenges"
branch_labels = None
depends_on = None

_BIND = op.get_bind()
_IS_PG = _BIND.dialect.name == "postgresql"


def upgrade() -> None:
    if not _IS_PG:
        return
    with op.batch_alter_table("challenges") as batch:
        batch.alter_column(
            "completed",
            type_=sa.Boolean(),
            postgresql_using="completed::int::boolean",
            existing_nullable=False,
        )
        batch.alter_column(
            "active",
            type_=sa.Boolean(),
            postgresql_using="active::int::boolean",
            existing_nullable=False,
        )


def downgrade() -> None:
    if not _IS_PG:
        return
    with op.batch_alter_table("challenges") as batch:
        batch.alter_column(
            "active",
            type_=sa.Integer(),
            postgresql_using="active::int",
            existing_nullable=False,
        )
        batch.alter_column(
            "completed",
            type_=sa.Integer(),
            postgresql_using="completed::int",
            existing_nullable=False,
        )
