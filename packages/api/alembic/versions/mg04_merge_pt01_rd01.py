"""merge pt01 (index trigram entités) et rd01 (user_content_status.completed_at).

Aucun changement de schéma. Les deux révisions descendent de `181c618da382` et
ont été mergées séparément dans `main`, laissant deux heads — `alembic upgrade
head` (rejoué au boot de chaque conteneur Railway par le `Dockerfile`) échoue
tant qu'ils ne sont pas réconciliés.
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
