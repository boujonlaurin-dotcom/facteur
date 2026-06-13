"""merge 22a1 interest_state + cta01 cluster_title_annotations

Hotfix : les PRs Story 22.1 (interest_state + favoris) et perspectives 7.4
(cluster_title_annotations) ont mergé en parallèle deux migrations descendant
toutes deux de `ad01_add_is_ad_to_contents` → branchpoint Alembic, 2 heads.
Le `Dockerfile` exécute `alembic upgrade head` (singulier) au boot Railway et
échoue avec "Multiple head revisions are present" → la prod est restée figée
sur `cta01_cluster_title_annotations` et `22a1_interest_state_favorites` n'a
jamais été appliquée. Conséquence : les colonnes `user_interests.state`,
`user_sources.state` et les tables `user_favorite_*` n'existent pas en prod,
toutes les requêtes feed renvoient `UndefinedColumn` → /api/feed/* en 500.

Cette révision unifie le graphe sans DDL : au prochain boot, Alembic
appliquera naturellement `22a1` (DDL + backfill embarqué) puis ce merge.

Revision ID: 5de67819bc61
Revises: 22a1_interest_state_favorites, cta01_cluster_title_annotations
Create Date: 2026-05-18 16:32:54.816174

"""

revision: str = "5de67819bc61"
down_revision: tuple[str, ...] = (
    "22a1_interest_state_favorites",
    "cta01_cluster_title_annotations",
)
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
