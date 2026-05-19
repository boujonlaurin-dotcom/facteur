"""Story 23.3 : auto-downgrade des custom_topic en favori → followed.

Un favori `kind=custom_topic` résolvait son filtre vers `slug_parent` (un des
51 slugs Mistral), donc « Plongée » ramenait tout le sport. La Story 23.3
interdit l'état `favorite` pour les custom_topic ; pour ne pas laisser de
favoris incohérents en base, cette migration :

1. Met `user_topic_profiles.state` de `favorite` → `followed` (l'utilisateur
   continue de bénéficier du boost scoring du feed via UserCustomTopicLayer).
2. Supprime les rows de `user_favorite_interests` qui référencent un
   `custom_topic_id` (la « tournée du jour » n'affichera plus de section
   custom_topic).

Les positions restantes peuvent contenir des trous — c'est intentionnel et
inoffensif : `GET /user/interests` les retourne triés par position et le
prochain `reorder` côté mobile compactera 0..N-1.

Revision ID: 23a3_custom_topic_fav_drop
Revises: vf02_favorite_veille_target
Create Date: 2026-05-19

"""

from alembic import op

revision: str = "23a3_custom_topic_fav_drop"
down_revision: str | None = "vf02_favorite_veille_target"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    op.execute(
        "UPDATE user_topic_profiles SET state = 'followed' WHERE state = 'favorite'"
    )
    op.execute(
        "DELETE FROM user_favorite_interests WHERE custom_topic_id IS NOT NULL"
    )


def downgrade() -> None:
    # Pas de downgrade fonctionnel : les favoris custom_topic supprimés sont
    # perdus. La colonne `state` reste valide (l'enum InterestState contient
    # toujours FAVORITE, utilisé par les thèmes/sources).
    pass
