"""Story 35.1 — analyse des angles (6C) : une analyse par sujet, liée aux articles.

Strictement additive : deux tables neuves, aucune colonne existante touchée.
`main` (staging) et `production` partagent la DB Supabase et rejouent tous deux
`alembic upgrade head` au boot — des tables neuves sont invisibles pour le backend
prod qui tourne encore sur l'ancien code.

Rejouable (`IF NOT EXISTS`), comme `tr01_essentiel_triage` : la même DDL peut être
vue deux fois par la DB partagée. `op.create_table(if_not_exists=True)` n'est **pas**
suffisant (la table est recréée et Postgres lève `DuplicateTable`), d'où le DDL brut.

Écrite à la main plutôt qu'autogénérée : `--autogenerate` ramasse ici un drift
pré-existant volumineux (tables prod absentes de `app.models`) et proposerait de les
**supprimer**. Cf. docs/runbooks/recover-from-alembic-drift.md.

Tables backend-only : RLS activée + `REVOKE ALL FROM anon, authenticated`, même
convention que `sec02_lock_down_new_public_tables` (advisor `rls_disabled_in_public`).

`perspective_analyses` n'est pas touchée : elle est dépréciée mais sa suppression est
un `DROP`, donc un cycle hebdo ultérieur (expand-contract).

Revision ID: ca01_coverage_analyses
Revises: su03_support_link_delivery
"""

from collections.abc import Sequence

from alembic import op

revision: str = "ca01_coverage_analyses"
down_revision: str | Sequence[str] | None = "su03_support_link_delivery"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_BACKEND_ONLY_TABLES = ("coverage_analyses", "coverage_analysis_articles")


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS coverage_analyses (
            id UUID PRIMARY KEY,
            subject_key VARCHAR(40) NOT NULL,
            consensus JSONB NOT NULL,
            qualifier VARCHAR(16),
            state VARCHAR(16) NOT NULL DEFAULT 'available',
            model_version VARCHAR(64),
            corpus_domains TEXT[] NOT NULL DEFAULT '{}',
            coverage_count INTEGER NOT NULL DEFAULT 0,
            generated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            CONSTRAINT uq_coverage_analyses_subject_key UNIQUE (subject_key),
            CONSTRAINT ck_coverage_analyses_state
                CHECK (state IN ('available', 'pending', 'unavailable')),
            CONSTRAINT ck_coverage_analyses_qualifier
                CHECK (qualifier IS NULL
                       OR qualifier IN ('polarized', 'varied', 'convergent'))
        )
        """
    )
    # Fraîcheur : le Reader ne sert qu'une analyse récente, et la purge future
    # balaiera par date.
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_coverage_analyses_generated_at "
        "ON coverage_analyses (generated_at DESC)"
    )
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS coverage_analysis_articles (
            coverage_analysis_id UUID NOT NULL
                REFERENCES coverage_analyses(id) ON DELETE CASCADE,
            content_id UUID NOT NULL
                REFERENCES contents(id) ON DELETE CASCADE,
            created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            PRIMARY KEY (coverage_analysis_id, content_id)
        )
        """
    )
    # Sens de lecture du Reader : content_id → analyse. La PK composite indexe
    # l'autre sens (analyse → articles).
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_coverage_analysis_articles_content_id "
        "ON coverage_analysis_articles (content_id)"
    )

    for table in _BACKEND_ONLY_TABLES:
        op.execute(f"ALTER TABLE {table} ENABLE ROW LEVEL SECURITY")
        op.execute(f"REVOKE ALL ON TABLE {table} FROM anon, authenticated")


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_coverage_analysis_articles_content_id")
    op.execute("DROP TABLE IF EXISTS coverage_analysis_articles")
    op.execute("DROP INDEX IF EXISTS ix_coverage_analyses_generated_at")
    op.execute("DROP TABLE IF EXISTS coverage_analyses")
