"""source_coverage_themes — couverture éditoriale data-driven des sources.

Ajoute une colonne nullable `sources.coverage_themes` (ARRAY de thèmes)
dérivée par un job périodique à partir du volume réel de `contents.theme`
sur 90 jours. Sert la **découverte** (recall large : « étoffer un thème »,
catalogue par thème) — distincte de `secondary_themes` qui reste l'input
**précis** du scoring (non touché ici). Cf. story 22.5 / hand-off A.

Purement additive (ADD COLUMN nullable) → sûre en expand-contract sur la DB
partagée staging/prod : le backend prod (ancien code) ignore la colonne
jusqu'au passage hebdo. Migration idempotente (no-op si la colonne existe).

Head précédent : ``ue01_user_entity_affinity``. Après : 1 seul head (cv01).
"""

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import ARRAY

from alembic import op

revision: str = "cv01_source_coverage_themes"
down_revision: str | None = "ue01_user_entity_affinity"
branch_labels: str | None = None
depends_on: str | None = None

_TABLE = "sources"
_COLUMN = "coverage_themes"


def upgrade() -> None:
    bind = op.get_bind()
    cols = {c["name"] for c in sa.inspect(bind).get_columns(_TABLE)}
    if _COLUMN in cols:
        return
    op.add_column(_TABLE, sa.Column(_COLUMN, ARRAY(sa.Text()), nullable=True))


def downgrade() -> None:
    bind = op.get_bind()
    cols = {c["name"] for c in sa.inspect(bind).get_columns(_TABLE)}
    if _COLUMN not in cols:
        return
    op.drop_column(_TABLE, _COLUMN)
