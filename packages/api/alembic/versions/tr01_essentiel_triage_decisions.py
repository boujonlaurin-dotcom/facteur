"""Story 33.1 — table des décisions de tri de la carte « Ton Essentiel ».

Strictement additive : une seule table neuve, aucune colonne existante touchée.
`main` (staging) et `production` partagent la DB Supabase et rejouent tous deux
`alembic upgrade head` au boot — une table neuve est invisible pour le backend
prod qui tourne encore sur l'ancien code.

Rejouable (`IF NOT EXISTS`), comme `rd01_ucs_completed_at` : la même DDL peut
être vue deux fois par la DB partagée. `op.create_table(if_not_exists=True)`
n'est **pas** suffisant ici (vérifié sur Alembic 1.18.4 : la table est recréée et
Postgres lève `DuplicateTable`), d'où le DDL brut.

Écrite à la main plutôt qu'autogénérée : `--autogenerate` ramasse ici un drift
pré-existant volumineux (tables prod absentes de `app.models`, comme
`article_feedback`, `app_config`, `nps_responses`, `source_search_cache`) et
proposerait de les **supprimer**. Cf. docs/runbooks/recover-from-alembic-drift.md.

Revision ID: tr01_essentiel_triage
Revises: mg06_merge_cq01_st02
"""

from collections.abc import Sequence

from alembic import op

revision: str = "tr01_essentiel_triage"
down_revision: str | Sequence[str] | None = "mg06_merge_cq01_st02"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS essentiel_triage_decisions (
            id UUID PRIMARY KEY,
            user_id UUID NOT NULL,
            content_id UUID NOT NULL
                REFERENCES contents(id) ON DELETE CASCADE,
            digest_date DATE NOT NULL,
            decision VARCHAR(12) NOT NULL,
            rank SMALLINT,
            slate_size SMALLINT,
            decided_via VARCHAR(8),
            latency_ms INTEGER,
            created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            CONSTRAINT uq_essentiel_triage_user_content_date
                UNIQUE (user_id, content_id, digest_date),
            CONSTRAINT ck_essentiel_triage_decision
                CHECK (decision IN ('keep', 'later', 'pass')),
            CONSTRAINT ck_essentiel_triage_decided_via
                CHECK (decided_via IN ('swipe', 'button'))
        )
        """
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_essentiel_triage_decisions_content_id "
        "ON essentiel_triage_decisions (content_id)"
    )
    # Dénominateur de la jauge : toutes les décisions d'un user sur un jour.
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_essentiel_triage_user_date "
        "ON essentiel_triage_decisions (user_id, digest_date)"
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_essentiel_triage_user_date")
    op.execute("DROP INDEX IF EXISTS ix_essentiel_triage_decisions_content_id")
    op.execute("DROP TABLE IF EXISTS essentiel_triage_decisions")
