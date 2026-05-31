"""data: désactiver France Info — Vrai ou Fake (doublon francetvinfo.fr).

La source 'France Info — Vrai ou Fake' (feed vrai-ou-fake.rss) est un sous-flux
du même domaine que 'France Info' (feed titres.rss). Avec les deux curated,
source_ids est artificiellement gonflé dans le clustering et les perspectives
affichent des doublons (même domaine, titres similaires).

Fix: is_curated=false — la source principale France Info reste active.
"""

from alembic import op

revision: str = "dd01_franceinfo_dedup"
down_revision: str | None = "gr01_la_grille_du_jour"
branch_labels: str | None = None
depends_on: str | None = None

_SOURCE_ID = "b71e6b5f-4995-43e3-990a-5674c719c737"


def upgrade() -> None:
    op.execute(
        f"UPDATE sources SET is_curated = false WHERE id = '{_SOURCE_ID}'"
    )


def downgrade() -> None:
    op.execute(
        f"UPDATE sources SET is_curated = true WHERE id = '{_SOURCE_ID}'"
    )
