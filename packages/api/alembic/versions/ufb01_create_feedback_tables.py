"""Create feedback tables (digest_sentiments, feedback_invites) for Epic 13.

Revision ID: ufb01
Revises: au02_api_usage_tokens
Create Date: 2026-06-29

SQL to run manually in Supabase SQL Editor:

CREATE TABLE IF NOT EXISTS digest_sentiments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    digest_date DATE NOT NULL,
    sentiment VARCHAR(10) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_digest_sentiments_user_date UNIQUE (user_id, digest_date)
);
CREATE INDEX IF NOT EXISTS ix_digest_sentiments_user_id ON digest_sentiments (user_id);
CREATE INDEX IF NOT EXISTS ix_digest_sentiments_digest_date ON digest_sentiments (digest_date);

CREATE TABLE IF NOT EXISTS feedback_invites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    segment VARCHAR(20),
    shown_count INTEGER NOT NULL DEFAULT 0,
    last_shown_at TIMESTAMPTZ,
    snoozed_until TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_feedback_invites_user UNIQUE (user_id)
);
"""

from typing import Sequence, Union

from alembic import op


# revision identifiers, used by Alembic.
revision: str = 'ufb01'
down_revision: Union[str, Sequence[str]] = 'au02_api_usage_tokens'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Additive only — safe. IF NOT EXISTS pour idempotence si créé
    # manuellement dans Supabase avant le tracking alembic.
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS digest_sentiments (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id UUID NOT NULL,
            digest_date DATE NOT NULL,
            sentiment VARCHAR(10) NOT NULL,
            created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            CONSTRAINT uq_digest_sentiments_user_date UNIQUE (user_id, digest_date)
        )
        """
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_digest_sentiments_user_id "
        "ON digest_sentiments (user_id)"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_digest_sentiments_digest_date "
        "ON digest_sentiments (digest_date)"
    )
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS feedback_invites (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id UUID NOT NULL,
            status VARCHAR(20) NOT NULL DEFAULT 'pending',
            segment VARCHAR(20),
            shown_count INTEGER NOT NULL DEFAULT 0,
            last_shown_at TIMESTAMPTZ,
            snoozed_until TIMESTAMPTZ,
            created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            CONSTRAINT uq_feedback_invites_user UNIQUE (user_id)
        )
        """
    )


def downgrade() -> None:
    op.drop_table('feedback_invites')
    op.drop_index('ix_digest_sentiments_digest_date', table_name='digest_sentiments')
    op.drop_index('ix_digest_sentiments_user_id', table_name='digest_sentiments')
    op.drop_table('digest_sentiments')
