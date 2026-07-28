"""user_sources.notify — cloche « alerte source rare » (Epic 30, story 30.2).

Ajoute une colonne nullable `notify BOOLEAN` sur `user_sources` : l'utilisateur
demande à être prévenu à chaque parution d'une source qui publie moins d'une
fois par semaine (plafond de 5 cloches, appliqué côté application).

Purement additive (ADD COLUMN nullable, sans server_default fonctionnel) → sûre
en expand-contract sur la DB partagée staging/prod : le backend `production`
(ancien code) ignore la colonne jusqu'au passage hebdo, aucune 2ᵉ étape de
contract requise. Lue partout comme `notify IS TRUE`, donc `NULL` = pas de
cloche, identique à `false`.

L'index partiel sert le producteur, qui part des contenus publiés dans les
dernières 24 h et remonte vers les abonnés : il ne balaye que les quelques
lignes réellement abonnées.

Migration idempotente (no-op si la colonne / l'index existent déjà).
Head précédent : ``mg04_merge_pt01_rd01``. Après : 1 seul head (sa01).
"""

import sqlalchemy as sa

from alembic import op

revision: str = "sa01_user_sources_notify"
down_revision: str | None = "mg04_merge_pt01_rd01"
branch_labels: str | None = None
depends_on: str | None = None

_TABLE = "user_sources"
_COLUMN = "notify"
_INDEX = "ix_user_sources_notify_source"


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    cols = {c["name"] for c in inspector.get_columns(_TABLE)}
    if _COLUMN not in cols:
        op.add_column(_TABLE, sa.Column(_COLUMN, sa.Boolean(), nullable=True))

    indexes = {i["name"] for i in inspector.get_indexes(_TABLE)}
    if _INDEX not in indexes:
        op.create_index(
            _INDEX,
            _TABLE,
            ["source_id"],
            postgresql_where=sa.text(f"{_COLUMN} IS TRUE"),
        )


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    indexes = {i["name"] for i in inspector.get_indexes(_TABLE)}
    if _INDEX in indexes:
        op.drop_index(_INDEX, table_name=_TABLE)

    cols = {c["name"] for c in inspector.get_columns(_TABLE)}
    if _COLUMN in cols:
        op.drop_column(_TABLE, _COLUMN)
