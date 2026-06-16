"""drop obsolete article extraction timestamp — DROP DIFFÉRÉ (expand-contract)

Revision ID: ex01_drop_extraction_ts
Revises: gh01_grille_hybrid_word

⚠️ EXPAND-CONTRACT — le DROP est volontairement REPORTÉ.

`contents.extraction_attempted_at` n'est plus utilisée par `main`, mais la DB
Supabase est PARTAGÉE avec le backend prod (branche `production`, plus ancienne)
qui l'utilise encore : `app/models/content.py` la mappe et `sync_service`
l'ÉCRIT à chaque sync. Tant que prod tourne ce code, dropper la colonne casse
toutes les requêtes Content en prod (UndefinedColumn).

Cette révision est donc un NO-OP : elle matérialise l'étape de la chaîne (jamais
appliquée — la DB était figée sur `mg01` à cause du fork multi-head). Le vrai
`DROP COLUMN` fera l'objet d'une migration séparée lors d'un cycle hebdo
ULTÉRIEUR, une fois la branche `production` avancée vers du code qui n'utilise
plus la colonne. Voir docs/runbooks/recover-from-alembic-drift.md.
"""

from collections.abc import Sequence

revision: str = "ex01_drop_extraction_ts"
down_revision: str | None = "gh01_grille_hybrid_word"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # DROP différé (expand-contract, DB partagée prod) — voir docstring.
    # Migration de suivi à créer post-cutover prod :
    #   op.drop_column("contents", "extraction_attempted_at")
    pass


def downgrade() -> None:
    pass
