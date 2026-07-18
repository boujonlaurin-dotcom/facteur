"""wl01 — champs comité de revue sur waitlist_entries.

Le formulaire « Rejoindre le comité de revue » de la page /methodologie du site
poste sur /api/waitlist avec deux champs supplémentaires : une motivation en
texte libre et l'envie de recevoir la méthode complète. On les persiste sur la
ligne waitlist plutôt que de les perdre.

Purement additive (2 ADD COLUMN nullables, sans server_default) → sûre en
expand-contract sur la DB partagée staging/prod. Migration idempotente
(no-op si les colonnes existent déjà).

Head précédent : ``es01_essentiel_placement``. Après : 1 seul head (wl01).
"""

import sqlalchemy as sa

from alembic import op

revision: str = "wl01_waitlist_comite_fields"
down_revision: str | None = "es01_essentiel_placement"
branch_labels: str | None = None
depends_on: str | None = None

_TABLE = "waitlist_entries"
_COLUMNS = (
    ("motivation", sa.Text()),
    ("methode_complete", sa.Boolean()),
)


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    cols = {c["name"] for c in inspector.get_columns(_TABLE)}
    for name, type_ in _COLUMNS:
        if name in cols:
            continue
        op.add_column(_TABLE, sa.Column(name, type_, nullable=True))


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    cols = {c["name"] for c in inspector.get_columns(_TABLE)}
    for name, _ in _COLUMNS:
        if name not in cols:
            continue
        op.drop_column(_TABLE, name)
