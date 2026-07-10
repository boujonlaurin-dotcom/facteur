"""user_entity_affinity — affinité positive apprise sur entités nommées (PR2).

Table miroir de `user_subtopics` côté entités : 1 ligne par
``(user_id, entity_canonical)`` avec un poids ``affinity`` borné [0.1, 3.0]
(neutre 1.0), un ``interaction_count`` et un decay quotidien vers 1.0. Alimente
le pilier Pertinence (« Parce que tu lis souvent {entité} ») sans vectorisation.

Additive (CREATE TABLE pur + index) → sûre en expand-contract sur la DB
partagée staging/prod : le backend prod (ancien code) ignore la table jusqu'au
passage hebdo. Migration idempotente (no-op si la table existe déjà).

Head précédent : ``pc02_api_usage_cached_tokens`` (#914). Après : 1 seul
head (ue01).
"""

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID as PGUUID

from alembic import op

revision: str = "ue01_user_entity_affinity"
down_revision: str | None = "pc02_api_usage_cached_tokens"
branch_labels: str | None = None
depends_on: str | None = None

_TABLE = "user_entity_affinity"
_INDEX = "ix_user_entity_affinity_user_id"
_UQ = "uq_user_entity_affinity_user_entity"


def upgrade() -> None:
    bind = op.get_bind()
    if sa.inspect(bind).has_table(_TABLE):
        return
    op.create_table(
        _TABLE,
        sa.Column("id", PGUUID(as_uuid=True), nullable=False),
        sa.Column("user_id", PGUUID(as_uuid=True), nullable=False),
        sa.Column("entity_canonical", sa.Text(), nullable=False),
        sa.Column(
            "affinity",
            sa.Float(),
            server_default=sa.text("1.0"),
            nullable=False,
        ),
        sa.Column(
            "interaction_count",
            sa.Integer(),
            server_default=sa.text("0"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["user_id"], ["user_profiles.user_id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "entity_canonical", name=_UQ),
    )
    op.create_index(_INDEX, _TABLE, ["user_id"])


def downgrade() -> None:
    bind = op.get_bind()
    if not sa.inspect(bind).has_table(_TABLE):
        return
    op.drop_index(_INDEX, table_name=_TABLE)
    op.drop_table(_TABLE)
