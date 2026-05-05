"""merge lf01 + sp01 heads

Revision ID: ls01
Revises: lf01, sp01
Create Date: 2026-05-03 00:00:00.000000

Migration de merge no-op : `lf01` (user_letter_progress) et `sp01`
(whitelist sport) ont été appliquées indépendamment sur main, créant
deux heads. Cette révision les unifie pour que `alembic upgrade head`
reste déterministe.
"""

from collections.abc import Sequence

revision: str = "ls01"
down_revision: str | Sequence[str] | None = ("lf01", "sp01")
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
