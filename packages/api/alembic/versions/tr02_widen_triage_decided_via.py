"""Story 33.2 — élargit `decided_via` à la modalité `read` (lecture depuis la
pile : le tap ouvre l'article, la lecture effective vaut « Je garde »).

Strictement additive au sens expand-contract : `main` (staging) et `production`
partagent la DB Supabase et rejouent tous deux `alembic upgrade head` au boot.
Élargir un CHECK ne rend invalide aucune écriture existante — le backend
`production`, qui n'émet que `swipe`/`button`, reste valide sous la contrainte
élargie. `VARCHAR(8)` accueille `read` sans changement de type.

Rejouable : `DROP CONSTRAINT IF EXISTS` puis `ADD CONSTRAINT` — la même DDL
peut être vue deux fois par la DB partagée sans erreur.

Revision ID: tr02_widen_triage_via
Revises: as01_dismissed_alert_targets
"""

from collections.abc import Sequence

from alembic import op

revision: str = "tr02_widen_triage_via"
# `as01` (alertes, mergé depuis main) et non `tr01` : les deux descendaient de
# `tr01` et forkaient la chaîne en 2 heads — le boot Railway refuse de démarrer
# sur une chaîne multi-heads. tr02 n'étant pas encore poussé, il est re-parenté
# plutôt que mergé.
down_revision: str | Sequence[str] | None = "as01_dismissed_alert_targets"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute(
        "ALTER TABLE essentiel_triage_decisions "
        "DROP CONSTRAINT IF EXISTS ck_essentiel_triage_decided_via"
    )
    op.execute(
        "ALTER TABLE essentiel_triage_decisions "
        "ADD CONSTRAINT ck_essentiel_triage_decided_via "
        "CHECK (decided_via IN ('swipe', 'button', 'read'))"
    )


def downgrade() -> None:
    # Resserrer exigerait de purger les lignes `read` d'abord — on ne détruit
    # pas de données au downgrade : la contrainte élargie reste en place.
    pass
