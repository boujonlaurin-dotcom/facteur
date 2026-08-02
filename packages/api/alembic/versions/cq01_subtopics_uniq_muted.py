"""Curation perso — hygiène user_subtopics + purge intérêts contredits (C-1).

Trois opérations, dans l'ordre :

1. **Dédup** ``user_subtopics`` sur ``(user_id, topic_slug)`` — garde la ligne
   de plus grand ``weight`` (5 doublons / 4 comptes au 2026-08-02). La
   contrainte d'unicité d'origine (``uq_user_subtopics_user_topic``) avait été
   droppée par accident par un ``--autogenerate`` (cf. ``4d497ce7bcc2``).
2. **Contrainte** ``UNIQUE (user_id, topic_slug)`` + **index** ``(user_id)`` —
   rétablit l'unicité (upsert atomique) et supprime le seq scan feed/digest
   (la table n'avait aucun index).
3. **Purge** des lignes ``user_interests`` sur un thème que l'utilisateur a
   explicitement **muté** (``user_personalization.muted_themes``) — 53 lignes /
   27 comptes au 02/08. Elles étaient fabriquées passivement par
   ``_adjust_interest_weight`` (corrigé dans la même PR) et affichées à tort
   dans « Mes intérêts ».

Idempotente (rejouable au boot des deux backends Railway) et sûre en
expand-contract : la DB est partagée staging/prod. La contrainte n'interdit
qu'un doublon que le vieux code ``production`` produit ~5×/vie-de-table (course
SEEN/CONSUMED). Le DELETE muté est à **rejouer une fois après la release hebdo**
— le temps que ``production`` prenne le correctif de code, il peut recréer
quelques lignes.

Head précédent : ``sa02_alerts_v2``. Après : 1 seul head (cq01).
"""

import sqlalchemy as sa

from alembic import op

revision: str = "cq01_subtopics_uniq_muted"
down_revision: str | None = "sa02_alerts_v2"
branch_labels: str | None = None
depends_on: str | None = None

_TABLE = "user_subtopics"
_UNIQUE = "uq_user_subtopics_user_topic"
_INDEX = "ix_user_subtopics_user_id"


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)

    # 1. Dédup préalable (garde le plus grand weight, puis le plus récent).
    #    Idempotent : no-op au 2ᵉ passage (plus aucun rn > 1).
    op.execute(
        """
        DELETE FROM user_subtopics
        WHERE id IN (
          SELECT id FROM (
            SELECT id, ROW_NUMBER() OVER (
              PARTITION BY user_id, topic_slug
              ORDER BY weight DESC, created_at DESC
            ) AS rn
            FROM user_subtopics
          ) t WHERE rn > 1
        )
        """
    )

    # 2a. Contrainte d'unicité (idempotent : garde sur pg_constraint).
    uniques = {u["name"] for u in inspector.get_unique_constraints(_TABLE)}
    if _UNIQUE not in uniques:
        op.create_unique_constraint(_UNIQUE, _TABLE, ["user_id", "topic_slug"])

    # 2b. Index sur user_id (idempotent).
    indexes = {i["name"] for i in inspector.get_indexes(_TABLE)}
    if _INDEX not in indexes:
        op.create_index(_INDEX, _TABLE, ["user_id"])

    # 3. Purge des intérêts contredisant un mute (idempotent : no-op si vide).
    op.execute(
        """
        DELETE FROM user_interests ui
        USING user_personalization up
        WHERE up.user_id = ui.user_id
          AND ui.interest_slug = ANY(COALESCE(up.muted_themes, '{}'))
        """
    )


def downgrade() -> None:
    # Le DELETE (dédup + purge muted) n'est pas réversible — on ne restaure que
    # le schéma (index + contrainte).
    bind = op.get_bind()
    inspector = sa.inspect(bind)

    indexes = {i["name"] for i in inspector.get_indexes(_TABLE)}
    if _INDEX in indexes:
        op.drop_index(_INDEX, table_name=_TABLE)

    uniques = {u["name"] for u in inspector.get_unique_constraints(_TABLE)}
    if _UNIQUE in uniques:
        op.drop_constraint(_UNIQUE, _TABLE, type_="unique")
