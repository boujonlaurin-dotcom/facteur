"""interest state enum + favorites tables (Story 22.1).

Système d'intérêts unifié à 4 états (hidden/unfollowed/followed/favorite)
appliqué à user_interests, user_topic_profiles, user_sources. Deux nouvelles
tables (user_favorite_interests, user_favorite_sources) avec PK composite
(user_id, position 0..2) garantissant le cap dur à 3 favoris par catégorie.

Audit prod 2026-05-16 : 39 doublons (user_id, interest_slug) à dédupliquer
avant la création de la UNIQUE constraint. Migration de données conservatrice :
weight ≤ 0.5 → hidden ; priority_multiplier = 0.2 → hidden ; aucun favori
auto-promu (le user devra les déclarer explicitement via la nouvelle UI).
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "22a1_interest_state_favorites"
down_revision: str | None = "ad01_add_is_ad_to_contents"
branch_labels: str | None = None
depends_on: str | None = None


# Enum partagé par les 3 tables. create_type=False : la création est faite
# explicitement via .create() pour pouvoir checkfirst=True (idempotence) ;
# les sa.Column() qui le référencent ne doivent pas le recréer.
interest_state_enum = postgresql.ENUM(
    "hidden",
    "unfollowed",
    "followed",
    "favorite",
    name="interest_state",
    create_type=False,
)


def upgrade() -> None:
    bind = op.get_bind()

    interest_state_enum.create(bind, checkfirst=True)

    # Dedupe défensif sur user_interests (39 lignes en prod au 2026-05-16).
    # Garde la row de plus grand weight (signal ML) en cas de doublon.
    op.execute(
        """
        DELETE FROM user_interests
        WHERE id IN (
          SELECT id FROM (
            SELECT id, ROW_NUMBER() OVER (
              PARTITION BY user_id, interest_slug
              ORDER BY weight DESC, created_at DESC
            ) AS rn
            FROM user_interests
          ) t WHERE rn > 1
        )
        """
    )

    op.add_column(
        "user_interests",
        sa.Column(
            "state",
            interest_state_enum,
            nullable=False,
            server_default="followed",
        ),
    )
    op.add_column(
        "user_topic_profiles",
        sa.Column(
            "state",
            interest_state_enum,
            nullable=False,
            server_default="followed",
        ),
    )
    op.add_column(
        "user_sources",
        sa.Column(
            "state",
            interest_state_enum,
            nullable=False,
            server_default="followed",
        ),
    )

    op.create_unique_constraint(
        "user_interests_user_slug_uniq",
        "user_interests",
        ["user_id", "interest_slug"],
    )

    op.create_table(
        "user_favorite_interests",
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("position", sa.SmallInteger(), nullable=False),
        sa.Column("interest_slug", sa.String(length=50), nullable=True),
        sa.Column("custom_topic_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("NOW()"),
        ),
        sa.PrimaryKeyConstraint("user_id", "position"),
        sa.ForeignKeyConstraint(
            ["user_id"], ["user_profiles.user_id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["custom_topic_id"], ["user_topic_profiles.id"], ondelete="CASCADE"
        ),
        sa.CheckConstraint(
            "position BETWEEN 0 AND 2",
            name="user_favorite_interests_position_range",
        ),
        sa.CheckConstraint(
            "(interest_slug IS NOT NULL)::int + (custom_topic_id IS NOT NULL)::int = 1",
            name="user_favorite_interests_target_xor",
        ),
    )

    op.create_table(
        "user_favorite_sources",
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("position", sa.SmallInteger(), nullable=False),
        sa.Column("source_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("NOW()"),
        ),
        sa.PrimaryKeyConstraint("user_id", "position"),
        sa.ForeignKeyConstraint(
            ["user_id"], ["user_profiles.user_id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(["source_id"], ["sources.id"], ondelete="CASCADE"),
        sa.UniqueConstraint(
            "user_id", "source_id", name="user_favorite_sources_user_source_uniq"
        ),
        sa.CheckConstraint(
            "position BETWEEN 0 AND 2",
            name="user_favorite_sources_position_range",
        ),
    )

    # Migration de données conservatrice (pas de favori auto-promu).
    op.execute("UPDATE user_interests SET state = 'hidden' WHERE weight <= 0.5")
    op.execute(
        "UPDATE user_sources SET state = 'hidden' WHERE priority_multiplier = 0.2"
    )
    op.execute(
        "UPDATE user_topic_profiles SET state = 'hidden' WHERE priority_multiplier = 0.2"
    )


def downgrade() -> None:
    op.drop_table("user_favorite_sources")
    op.drop_table("user_favorite_interests")
    op.drop_constraint(
        "user_interests_user_slug_uniq", "user_interests", type_="unique"
    )
    op.drop_column("user_sources", "state")
    op.drop_column("user_topic_profiles", "state")
    op.drop_column("user_interests", "state")
    interest_state_enum.drop(op.get_bind(), checkfirst=True)
