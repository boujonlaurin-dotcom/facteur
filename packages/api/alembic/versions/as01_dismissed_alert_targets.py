"""Story 30.6 — mémoire des suggestions d'alerte refusées.

Deux colonnes, strictement **additives** : `user_personalization` porte déjà les
mutes et les `*_dismissed_at`, une table neuve pour deux listes d'IDs aurait été
du poids de schéma pour rien.

`UUID[]` typé, une colonne par famille de cible, plutôt qu'un seul `TEXT[]` de
clés « source:<uuid> » : c'est la forme des colonnes voisines (`muted_sources`
est déjà un `UUID[]`), et un `UUID[]` reste **joignable** — le jour où
l'exclusion devra descendre dans la requête candidate, elle le pourra sans
parser des chaînes en SQL.

Expand-contract respecté : `main` (staging) et `production` partagent la DB
Supabase et rejouent tous deux `alembic upgrade head` au boot. Le backend prod
tourne l'ancien code jusqu'à une semaine ; il n'écrit ni ne lit ces colonnes, et
ses `INSERT` les laissent au `DEFAULT '{}'`. Aucune étape de contraction n'est
nécessaire (rien à retirer, rien à renommer).

`NOT NULL DEFAULT '{}'` sur une table peuplée est sûr depuis PostgreSQL 11 : le
défaut est stocké en métadonnée, sans réécriture de table.

Rejouable : `ADD COLUMN IF NOT EXISTS`, comme les migrations précédentes de la
DB partagée, pour que la même DDL puisse être vue deux fois sans planter le boot
Railway.

Écrite à la main plutôt qu'autogénérée : `--autogenerate` ramasse ici le drift
pré-existant de la DB partagée (tables prod absentes de `app.models`) et
proposerait de les supprimer. Cf. docs/runbooks/recover-from-alembic-drift.md.

Revision ID: as01_dismissed_alert_targets
Revises: tr01_essentiel_triage
"""

from collections.abc import Sequence

from alembic import op

revision: str = "as01_dismissed_alert_targets"
down_revision: str | Sequence[str] | None = "tr01_essentiel_triage"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute(
        """
        ALTER TABLE user_personalization
        ADD COLUMN IF NOT EXISTS dismissed_alert_sources UUID[]
            NOT NULL DEFAULT '{}'
        """
    )
    op.execute(
        """
        ALTER TABLE user_personalization
        ADD COLUMN IF NOT EXISTS dismissed_alert_topics UUID[]
            NOT NULL DEFAULT '{}'
        """
    )


def downgrade() -> None:
    op.execute(
        "ALTER TABLE user_personalization DROP COLUMN IF EXISTS dismissed_alert_topics"
    )
    op.execute(
        "ALTER TABLE user_personalization "
        "DROP COLUMN IF EXISTS dismissed_alert_sources"
    )
