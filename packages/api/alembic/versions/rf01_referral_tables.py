"""Story partage.2 — attribution de parrainage : code par utilisateur + attributions.

Strictement additive : deux tables neuves, aucune colonne existante touchée.
`main` (staging) et `production` partagent la DB Supabase et rejouent tous deux
`alembic upgrade head` au boot — des tables neuves sont invisibles pour le backend
prod qui tourne encore sur l'ancien code.

Rejouable (`IF NOT EXISTS`), comme `ca01_coverage_analyses` : la même DDL peut être
vue deux fois par la DB partagée. `op.create_table(if_not_exists=True)` n'est **pas**
suffisant (Postgres lève `DuplicateTable`), d'où le DDL brut.

Écrite à la main plutôt qu'autogénérée : `--autogenerate` ramasse ici un drift
pré-existant volumineux (tables prod absentes de `app.models`) et proposerait de les
**supprimer**. Cf. docs/runbooks/recover-from-alembic-drift.md.

Les FK ciblent `user_profiles(user_id)` — l'id Supabase — et non `user_profiles(id)`,
qui est une PK technique distincte (cf. `app/models/user.py`).

Tables backend-only : RLS activée + `REVOKE ALL FROM anon, authenticated`, même
convention que `ca01` / `sec02_lock_down_new_public_tables`
(advisor `rls_disabled_in_public`).

Revision ID: rf01_referral_tables
Revises: ca01_coverage_analyses
"""

from collections.abc import Sequence

from alembic import op

revision: str = "rf01_referral_tables"
down_revision: str | Sequence[str] | None = "ca01_coverage_analyses"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_BACKEND_ONLY_TABLES = ("referral_codes", "referral_attributions")


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS referral_codes (
            user_id UUID PRIMARY KEY
                REFERENCES user_profiles(user_id) ON DELETE CASCADE,
            code VARCHAR(8) NOT NULL,
            created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            CONSTRAINT uq_referral_codes_code UNIQUE (code)
        )
        """
    )
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS referral_attributions (
            id UUID PRIMARY KEY,
            referred_user_id UUID NOT NULL UNIQUE
                REFERENCES user_profiles(user_id) ON DELETE CASCADE,
            code VARCHAR(8) NOT NULL,
            surface VARCHAR(40),
            platform VARCHAR(16),
            store VARCHAR(16),
            utm_source VARCHAR(100),
            utm_medium VARCHAR(100),
            utm_campaign VARCHAR(100),
            referrer_raw VARCHAR(2000),
            created_at TIMESTAMPTZ NOT NULL DEFAULT now()
        )
        """
    )
    # Sens de lecture de `joined_count` : code du parrain → filleuls.
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_referral_attributions_code "
        "ON referral_attributions (code)"
    )

    # `user_preferences` n'a aucun index en dehors de sa PK, or l'attribution
    # promeut le filtre (user_id, preference_key) d'un chemin admin à un chemin
    # utilisateur (une fois par installation). Additif, donc sans risque pour le
    # backend prod qui tourne encore sur l'ancien code.
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_user_preferences_user_key "
        "ON user_preferences (user_id, preference_key)"
    )

    for table in _BACKEND_ONLY_TABLES:
        op.execute(f"ALTER TABLE {table} ENABLE ROW LEVEL SECURITY")
        op.execute(f"REVOKE ALL ON TABLE {table} FROM anon, authenticated")


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_user_preferences_user_key")
    op.execute("DROP INDEX IF EXISTS ix_referral_attributions_code")
    op.execute("DROP TABLE IF EXISTS referral_attributions")
    op.execute("DROP TABLE IF EXISTS referral_codes")
