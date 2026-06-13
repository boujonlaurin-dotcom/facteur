"""merge au01 api_usage_events + b75132e0c6b5 event_rsvps

Hotfix : les PRs #818 (observabilité scaling, `au01_api_usage_events`) et
#828 (RSVP événement, `b75132e0c6b5`) ont mergé en parallèle deux migrations
descendant toutes deux de `gr02_grille_featured_article` → branchpoint
Alembic, 2 heads. Le `Dockerfile` exécute `alembic upgrade head` (singulier)
au boot Railway et échoue avec "Multiple head revisions are present" → la DB
est restée figée sur `b75132e0c6b5` (déployée en premier le 2026-06-11) et
`au01_api_usage_events` n'a jamais été appliquée : la table
`api_usage_events` n'existe pas, et tous les déploiements staging depuis le
merge de #818 (2026-06-12) plantent au boot.

Même incident que `5de67819bc61` (2026-05-18) : le hook
`post-edit-alembic-heads.sh` ne protège pas des merges GitHub parallèles.

Cette révision unifie le graphe sans DDL : au prochain boot, Alembic
appliquera naturellement `au01_api_usage_events` puis ce merge.

Revision ID: mg01_merge_au01_rsvps
Revises: au01_api_usage_events, b75132e0c6b5
Create Date: 2026-06-13

"""

revision: str = "mg01_merge_au01_rsvps"
down_revision: tuple[str, ...] = (
    "au01_api_usage_events",
    "b75132e0c6b5",
)
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
