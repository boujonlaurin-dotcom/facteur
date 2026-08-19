"""user_content_status: essentiel_last_shown_at (cooldown carrousel Essentiel)

Story 33.5 — espacer d'au moins 7 jours la réapparition d'un même article
injecté via le carrousel Phase B (`saved`/`quiet_sources`/`community`/
`new_source`) dans la pile Essentiel.

Additif pur, aucun backfill : `essentiel_last_shown_at IS NULL` signifie
« jamais montré via ce mécanisme », donc éligible immédiatement.

Revision ID: es01_essentiel_carousel_last_shown
Revises: su03_support_link_delivery
Create Date: 2026-08-19
"""

from collections.abc import Sequence

from alembic import op

revision: str = "es01_essentiel_carousel_last_shown"
down_revision: str | None = "su03_support_link_delivery"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Rejouable (IF NOT EXISTS) : la DB Supabase est partagée staging↔prod et le
    # Dockerfile rejoue `alembic upgrade head` au boot des deux services.
    op.execute(
        "ALTER TABLE user_content_status "
        "ADD COLUMN IF NOT EXISTS essentiel_last_shown_at TIMESTAMPTZ"
    )


def downgrade() -> None:
    op.execute(
        "ALTER TABLE user_content_status DROP COLUMN IF EXISTS essentiel_last_shown_at"
    )
