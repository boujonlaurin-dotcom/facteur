"""merge pt01 (index trigram entities) et rd01 (user_content_status.completed_at).

Aucun changement de schéma. Les deux révisions ont été mergées sur `main` le
même jour, chacune avec `down_revision = "181c618da382"` et sans révision de
merge : `alembic upgrade head` n'avait plus de cible unique, le boot Railway
échouait et l'app démarrait quand même (« Migrations failed … starting app
anyway ») sur un ORM mappant des colonnes absentes → 500 généralisés sur
staging.

Les deux branches ne touchent aucun objet commun (index d'expression sur
`contents` d'un côté, colonnes de `user_content_status` de l'autre), donc la
révision est vide.
"""

revision: str = "mg04_merge_pt01_rd01"
down_revision: tuple[str, ...] = (
    "pt01_contents_entities_trgm",
    "rd01_ucs_completed_at",
)
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
