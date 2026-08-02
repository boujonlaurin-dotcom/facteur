"""merge cq01 (hygiène user_subtopics + purge intérêts) et st02 (soutien Stripe).

Aucun changement de schéma. Les deux révisions ont down_revision =
"sa02_alerts_v2" (mergées sur `main` le même jour via des PRs distinctes) :
`alembic upgrade head` n'avait plus de cible unique côté CI. Les deux
branches ne touchent aucun objet commun (user_subtopics/user_interests d'un
côté, colonnes Stripe/supporter_messages de l'autre), donc la révision est
vide.
"""

from typing import Sequence, Union

revision: str = "mg06_merge_cq01_st02"
down_revision: Union[str, tuple[str, ...], None] = (
    "cq01_subtopics_uniq_muted",
    "st02_supporter_messages",
)
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
