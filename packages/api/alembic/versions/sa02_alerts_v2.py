"""Alertes v2 — mode filtré + cloche sur les sujets (Epic 30, story 30.3).

Trois ajouts strictement additifs :

- ``user_sources.notify_filtered BOOLEAN NULL`` — ``NULL``/``false`` = toutes
  les parutions, ``true`` = mode filtré (1 alerte/jour max, la mieux scorée).
- ``user_topic_profiles.notify`` / ``.notify_filtered`` — la même cloche, posée
  sur un sujet suivi au lieu d'une source.
- Index partiel ``ix_utp_notify`` pour le producteur sujet, qui part des
  utilisateurs et remonte vers leurs sujets sous cloche.

Purement additive (ADD COLUMN nullable sans server_default fonctionnel) → sûre
en expand-contract sur la DB partagée staging/prod : le backend ``production``
(ancien code) ignore les colonnes jusqu'au passage hebdo, aucune 2ᵉ étape de
contract requise. Lues partout comme ``IS TRUE``, donc ``NULL`` = pas de
cloche, identique à ``false``.

Migration idempotente (no-op si colonnes / index existent déjà).
Head précédent : ``mg05_merge_dg01_sa01``. Après : 1 seul head (sa02).
"""

import sqlalchemy as sa

from alembic import op

revision: str = "sa02_alerts_v2"
down_revision: str | None = "mg05_merge_dg01_sa01"
branch_labels: str | None = None
depends_on: str | None = None

_USER_SOURCES = "user_sources"
_TOPIC_PROFILES = "user_topic_profiles"
_UTP_NOTIFY_INDEX = "ix_utp_notify"


def _add_bool_column(inspector, table: str, column: str) -> None:
    cols = {c["name"] for c in inspector.get_columns(table)}
    if column not in cols:
        op.add_column(table, sa.Column(column, sa.Boolean(), nullable=True))


def _drop_column(inspector, table: str, column: str) -> None:
    cols = {c["name"] for c in inspector.get_columns(table)}
    if column in cols:
        op.drop_column(table, column)


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)

    _add_bool_column(inspector, _USER_SOURCES, "notify_filtered")
    _add_bool_column(inspector, _TOPIC_PROFILES, "notify")
    _add_bool_column(inspector, _TOPIC_PROFILES, "notify_filtered")

    indexes = {i["name"] for i in inspector.get_indexes(_TOPIC_PROFILES)}
    if _UTP_NOTIFY_INDEX not in indexes:
        op.create_index(
            _UTP_NOTIFY_INDEX,
            _TOPIC_PROFILES,
            ["user_id"],
            postgresql_where=sa.text("notify IS TRUE"),
        )


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)

    indexes = {i["name"] for i in inspector.get_indexes(_TOPIC_PROFILES)}
    if _UTP_NOTIFY_INDEX in indexes:
        op.drop_index(_UTP_NOTIFY_INDEX, table_name=_TOPIC_PROFILES)

    _drop_column(inspector, _TOPIC_PROFILES, "notify_filtered")
    _drop_column(inspector, _TOPIC_PROFILES, "notify")
    _drop_column(inspector, _USER_SOURCES, "notify_filtered")
