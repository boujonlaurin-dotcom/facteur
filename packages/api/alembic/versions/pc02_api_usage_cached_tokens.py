"""api_usage_events — capture des tokens de prompt caché·es (LR-1 PR 2)

Migration **additive** : ajoute `cached_prompt_tokens` (int, nullable) à
`api_usage_events`. Mistral renvoie `usage.prompt_tokens_details.cached_tokens`
quand un `prompt_cache_key` réutilise un préfixe de prompt déjà vu ; le persister
permet de mesurer (par `GROUP BY model`) le bénéfice du cache introduit sur les
prompts à gros préfixe stable (classification statique, entités, good-news).
Nullable car Brave n'a pas de tokens, un appel échoué avant réponse non plus, et
un appel sans cache hit renvoie 0. Non destructif, rollback trivial.

Head précédent : ufb01_create_feedback_tables (head courant de main). Après :
1 seul head (pc02).
"""

import sqlalchemy as sa

from alembic import op

revision: str = "pc02_api_usage_cached_tokens"
down_revision: str | None = "ufb01"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    op.add_column(
        "api_usage_events",
        sa.Column("cached_prompt_tokens", sa.Integer(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("api_usage_events", "cached_prompt_tokens")
