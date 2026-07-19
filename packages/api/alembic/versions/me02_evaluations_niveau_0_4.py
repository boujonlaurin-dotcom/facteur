"""media eval — élargit le CHECK ``niveau`` des évaluations de 0-2 à 0-4 (v1.3).

La grille v1.3 note **tous** les critères par niveaux, dont certains à 5 niveaux
(C1/C2/C3/C6 → niveau 4). Le CHECK ``ck_media_eval_evaluations_niveau`` posé par
``me01`` bornait ``niveau`` à 0-2 (v1.2, C9/C11 à 3 niveaux) : on l'élargit à 0-4.

**Expand additive, sûre en expand-contract sur la DB partagée staging/prod.**
Élargir un CHECK n'invalide jamais une ligne existante (0-2 ⊂ 0-4) : le backend
prod (ancien code ``production``) n'écrit que des niveaux 0-2, toujours valides
sous la contrainte élargie, jusqu'au passage hebdo. La chaîne ``alembic upgrade
head`` boote sur les DEUX services Railway → migration **idempotente** (DROP IF
EXISTS + ADD, rejouable sans erreur). Aucune donnée n'est réécrite.

``NOT VALID`` puis ``VALIDATE`` : évite un scan bloquant de la table à l'ADD ; le
VALIDATE est trivial ici (toutes les lignes 0-2 satisfont déjà 0-4).
"""

import sqlalchemy as sa

from alembic import op

revision: str = "me02_evaluations_niveau_0_4"
down_revision: str | None = "me01_media_eval_tables"
branch_labels: str | None = None
depends_on: str | None = None

_TABLE = "media_eval_evaluations"
_CONSTRAINT = "ck_media_eval_evaluations_niveau"
_CHECK_0_4 = "niveau IS NULL OR (niveau >= 0 AND niveau <= 4)"
_CHECK_0_2 = "niveau IS NULL OR (niveau >= 0 AND niveau <= 2)"


def _remplacer_check(expression: str) -> None:
    op.execute(f"ALTER TABLE {_TABLE} DROP CONSTRAINT IF EXISTS {_CONSTRAINT}")
    op.execute(
        f"ALTER TABLE {_TABLE} ADD CONSTRAINT {_CONSTRAINT} "
        f"CHECK ({expression}) NOT VALID"
    )
    op.execute(f"ALTER TABLE {_TABLE} VALIDATE CONSTRAINT {_CONSTRAINT}")


def upgrade() -> None:
    # No-op si la table n'existe pas encore (chaîne rejouée sur une DB partielle).
    if not sa.inspect(op.get_bind()).has_table(_TABLE):
        return
    _remplacer_check(_CHECK_0_4)


def downgrade() -> None:
    if not sa.inspect(op.get_bind()).has_table(_TABLE):
        return
    _remplacer_check(_CHECK_0_2)
