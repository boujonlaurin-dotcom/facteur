"""add is_ad column to contents

Détection des articles publicitaires / native ads dans le pipeline de
classification Pass 1 (mistral-small). NULL = non encore classifié (articles
antérieurs à la migration), traité comme False dans les filtres aval pour
préserver la compatibilité ascendante.
"""

import sqlalchemy as sa

from alembic import op

revision: str = "ad01_add_is_ad_to_contents"
down_revision: str | None = "sd01_soft_delete_user_profiles"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    op.add_column(
        "contents",
        sa.Column("is_ad", sa.Boolean(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("contents", "is_ad")
