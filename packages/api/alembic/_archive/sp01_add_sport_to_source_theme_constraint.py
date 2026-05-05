"""add_sport_to_source_theme_constraint

Revision ID: sp01
Revises: vl01, gn01
Create Date: 2026-05-02 21:00:00.000000

Étend `ck_source_theme_valid` pour autoriser le slug `sport`. Sans ce
fix, l'ingestion d'une source niche pour le thème Sport (présent côté
front et côté onboarding) viole la CHECK constraint et empoisonne la
session HTTP en cours.

Cette migration merge également les deux heads en attente (`vl01` et
`gn01`) pour rester sur un head unique.
"""

from collections.abc import Sequence

from alembic import op

revision: str = "sp01"
down_revision: str | Sequence[str] | None = ("vl01", "gn01")
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


_ALLOWED = (
    "tech",
    "society",
    "environment",
    "economy",
    "politics",
    "culture",
    "science",
    "international",
    "custom",
    "sport",
)


def upgrade() -> None:
    op.execute("ALTER TABLE sources DROP CONSTRAINT IF EXISTS ck_source_theme_valid")
    op.create_check_constraint(
        "ck_source_theme_valid",
        "sources",
        "theme IN (" + ", ".join(f"'{t}'" for t in _ALLOWED) + ")",
    )


def downgrade() -> None:
    op.execute("ALTER TABLE sources DROP CONSTRAINT IF EXISTS ck_source_theme_valid")
    op.create_check_constraint(
        "ck_source_theme_valid",
        "sources",
        "theme IN ('tech', 'society', 'environment', 'economy', 'politics', "
        "'culture', 'science', 'international', 'custom')",
    )
