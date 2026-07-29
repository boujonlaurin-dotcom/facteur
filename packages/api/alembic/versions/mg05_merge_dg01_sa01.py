"""merge dg01 (objectif du jour) et sa01 (alerte source rare).

Aucun changement de schéma. `dg01_daily_goal_user_profiles` (objectif quotidien,
arrivé sur `main` via #1011) et `sa01_user_sources_notify` (cloche « alerte
source rare », cette PR) descendent tous deux de `mg04_merge_pt01_rd01`,
laissant deux heads. `alembic upgrade head` — rejoué au boot de chaque conteneur
Railway par le `Dockerfile` — échoue tant qu'ils ne sont pas réconciliés. Les
deux révisions ne touchent aucun objet commun (`user_profiles` d'un côté,
`user_sources` de l'autre), donc la révision de merge est vide.
"""

revision: str = "mg05_merge_dg01_sa01"
down_revision: tuple[str, ...] = (
    "dg01_daily_goal_user_profiles",
    "sa01_user_sources_notify",
)
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
