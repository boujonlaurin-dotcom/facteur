"""Veille : lier chaque mot-clé à son angle (grappe) — angle = sujet + keywords.

Part B de la refonte curation veille :
- ADD veille_keywords.veille_topic_id (UUID, nullable, FK veille_topics.id
  ondelete CASCADE) — null = mot-clé global de la config.
- INDEX ix_veille_keywords_topic.
- Relâche l'unique de (veille_config_id, keyword) vers
  (veille_config_id, veille_topic_id, keyword) pour autoriser la même clé
  sous deux angles.

Ops explicites (style vf01, pas d'autogenerate aveugle). `downgrade` symétrique
(supprime d'abord les keywords rattachés à un angle pour ne pas violer l'ancien
unique au moment du recreate).

Revision ID: vk01_link_keywords_to_topics
Revises: dd01_franceinfo_dedup
Create Date: 2026-05-31

"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "vk01_link_keywords_to_topics"
down_revision: str | None = "dd01_franceinfo_dedup"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    op.add_column(
        "veille_keywords",
        sa.Column(
            "veille_topic_id",
            postgresql.UUID(as_uuid=True),
            nullable=True,
        ),
    )
    op.create_foreign_key(
        "fk_veille_keywords_topic",
        "veille_keywords",
        "veille_topics",
        ["veille_topic_id"],
        ["id"],
        ondelete="CASCADE",
    )
    op.create_index(
        "ix_veille_keywords_topic", "veille_keywords", ["veille_topic_id"]
    )

    op.drop_constraint("uq_veille_keywords", "veille_keywords", type_="unique")
    op.create_unique_constraint(
        "uq_veille_keywords",
        "veille_keywords",
        ["veille_config_id", "veille_topic_id", "keyword"],
    )


def downgrade() -> None:
    # Les keywords rattachés à un angle peuvent dupliquer (config, keyword) ;
    # on les retire avant de restaurer l'ancien unique plus strict.
    op.execute("DELETE FROM veille_keywords WHERE veille_topic_id IS NOT NULL")

    op.drop_constraint("uq_veille_keywords", "veille_keywords", type_="unique")
    op.create_unique_constraint(
        "uq_veille_keywords",
        "veille_keywords",
        ["veille_config_id", "keyword"],
    )

    op.drop_index("ix_veille_keywords_topic", table_name="veille_keywords")
    op.drop_constraint(
        "fk_veille_keywords_topic", "veille_keywords", type_="foreignkey"
    )
    op.drop_column("veille_keywords", "veille_topic_id")
