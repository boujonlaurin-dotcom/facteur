"""essentiel_placement — persister l'appartenance Essentiel/Flâner en DB.

Ajoute une colonne nullable `essentiel_mode BOOLEAN` sur `user_sources` et
`user_interests`. Jusqu'ici le *mode de placement* d'un favori (« Chaque jour
dans l'Essentiel » vs « Flâner ») ne vivait que dans les `SharedPreferences` du
device (clés `tournee_order_v1` / `pinned_tabs_order_v1`) : à la réinstallation
le favori survivait en DB mais son placement était silencieusement perdu. Cette
colonne fait de la DB la source de vérité durable.

Sémantique : `true` = Essentiel, `false` = Flâner, `NULL` = jamais placé
explicitement / legacy (backfillé depuis le device au premier cold-boot).

Purement additive (ADD COLUMN nullable, sans server_default fonctionnel) → sûre
en expand-contract sur la DB partagée staging/prod : le backend prod (ancien
code) ignore la colonne jusqu'au passage hebdo, aucune 2ᵉ étape de contract
requise. Migration idempotente (no-op si la colonne existe déjà).

Head précédent : ``me01_media_eval_tables``. Après : 1 seul head (es01).
"""

import sqlalchemy as sa

from alembic import op

revision: str = "es01_essentiel_placement"
down_revision: str | None = "me01_media_eval_tables"
branch_labels: str | None = None
depends_on: str | None = None

_COLUMN = "essentiel_mode"
_TABLES = ("user_sources", "user_interests")


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    for table in _TABLES:
        cols = {c["name"] for c in inspector.get_columns(table)}
        if _COLUMN in cols:
            continue
        op.add_column(table, sa.Column(_COLUMN, sa.Boolean(), nullable=True))


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    for table in _TABLES:
        cols = {c["name"] for c in inspector.get_columns(table)}
        if _COLUMN not in cols:
            continue
        op.drop_column(table, _COLUMN)
