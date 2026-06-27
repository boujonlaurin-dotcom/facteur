"""api_usage_events — capture des tokens prompt/completion (LR-1 PR 1)

Migration **additive** : ajoute `prompt_tokens` et `completion_tokens` (int,
nullable) à `api_usage_events`. Les réponses Mistral renvoient déjà
`usage.{prompt_tokens, completion_tokens}` ; les persister transforme le
compteur d'appels en modèle €/token (un `GROUP BY model` donne le € réel par
modèle / call_site). Nullable car Brave n'a pas de tokens et un appel échoué
avant réponse n'en a pas non plus. Non destructif, rollback trivial.

Head précédent : sec02_new_public_rls (head courant de main). Après : 1 seul
head (au02). `api_usage_events` a été introduite par au01, mais on chaîne sur le
head courant pour ne pas créer un 2e head (au01 a déjà des descendants).
"""

import sqlalchemy as sa

from alembic import op

revision: str = "au02_api_usage_tokens"
down_revision: str | None = "sec02_new_public_rls"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    op.add_column(
        "api_usage_events",
        sa.Column("prompt_tokens", sa.Integer(), nullable=True),
    )
    op.add_column(
        "api_usage_events",
        sa.Column("completion_tokens", sa.Integer(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("api_usage_events", "completion_tokens")
    op.drop_column("api_usage_events", "prompt_tokens")
