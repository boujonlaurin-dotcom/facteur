"""Story 23.1 PR-3 : 3ᵉ type de favori (veille) sur user_favorite_interests.

Ajoute la colonne `veille_config_id` (FK veille_configs.id ON DELETE CASCADE)
et remplace la CheckConstraint XOR par sa version 3-way. La veille devient un
favori au même titre qu'un Thème ou un Sujet personnalisé.

Revision ID: vf02_favorite_veille_target
Revises: vf01_veille_filter_refonte
Create Date: 2026-05-19

"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "vf02_favorite_veille_target"
down_revision: str | None = "vf01_veille_filter_refonte"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    op.drop_constraint(
        "user_favorite_interests_target_xor",
        "user_favorite_interests",
        type_="check",
    )
    op.add_column(
        "user_favorite_interests",
        sa.Column(
            "veille_config_id",
            postgresql.UUID(as_uuid=True),
            nullable=True,
        ),
    )
    op.create_foreign_key(
        "user_favorite_interests_veille_config_fk",
        "user_favorite_interests",
        "veille_configs",
        ["veille_config_id"],
        ["id"],
        ondelete="CASCADE",
    )
    op.create_check_constraint(
        "user_favorite_interests_target_xor_v2",
        "user_favorite_interests",
        "(interest_slug IS NOT NULL)::int "
        "+ (custom_topic_id IS NOT NULL)::int "
        "+ (veille_config_id IS NOT NULL)::int = 1",
    )


def downgrade() -> None:
    op.drop_constraint(
        "user_favorite_interests_target_xor_v2",
        "user_favorite_interests",
        type_="check",
    )
    op.drop_constraint(
        "user_favorite_interests_veille_config_fk",
        "user_favorite_interests",
        type_="foreignkey",
    )
    op.drop_column("user_favorite_interests", "veille_config_id")
    op.create_check_constraint(
        "user_favorite_interests_target_xor",
        "user_favorite_interests",
        "(interest_slug IS NOT NULL)::int + (custom_topic_id IS NOT NULL)::int = 1",
    )
