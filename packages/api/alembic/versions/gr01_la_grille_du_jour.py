"""la grille du jour — tables puzzle + état de partie (Story 24.1)

Migration additive : crée `grille_puzzles` (puzzle global daté, mot secret
serveur) et `grille_game_states` (une partie par user et par jour). Aucune
donnée existante touchée → pas de stamp prod requis.

Head précédent : cl01_drop_daily_top3.
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "gr01_la_grille_du_jour"
down_revision: str | None = "cl01_drop_daily_top3"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    op.create_table(
        "grille_puzzles",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            nullable=False,
        ),
        sa.Column("puzzle_date", sa.Date(), nullable=False),
        sa.Column("word", sa.String(length=8), nullable=False),
        sa.Column(
            "length",
            sa.SmallInteger(),
            nullable=False,
            server_default="6",
        ),
        sa.Column(
            "max_attempts",
            sa.SmallInteger(),
            nullable=False,
            server_default="6",
        ),
        sa.Column("indice", sa.Text(), nullable=False),
        sa.Column("theme", sa.String(), nullable=False),
        sa.Column("pourquoi", sa.Text(), nullable=False),
        sa.Column("numero", sa.String(), nullable=False),
        sa.Column("date_affichee", sa.String(), nullable=False),
        sa.Column("date_court", sa.String(), nullable=False),
        sa.Column("cancel", sa.String(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
        ),
        sa.UniqueConstraint("puzzle_date", name="uq_grille_puzzles_date"),
    )

    op.create_table(
        "grille_game_states",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            nullable=False,
        ),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("puzzle_date", sa.Date(), nullable=False),
        sa.Column(
            "guesses",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default="[]",
        ),
        sa.Column(
            "status",
            sa.String(),
            nullable=False,
            server_default="in_progress",
        ),
        sa.Column(
            "attempts",
            sa.SmallInteger(),
            nullable=False,
            server_default="0",
        ),
        sa.Column("finished_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint(
            "user_id", "puzzle_date", name="uq_grille_game_states_user_date"
        ),
    )
    op.create_index(
        "ix_grille_game_states_puzzle_date",
        "grille_game_states",
        ["puzzle_date"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_grille_game_states_puzzle_date", table_name="grille_game_states"
    )
    op.drop_table("grille_game_states")
    op.drop_table("grille_puzzles")
