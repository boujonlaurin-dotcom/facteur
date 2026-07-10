"""grille hybrid word occurrence — colonnes hybrid_* sur grille_puzzles.

Sélection hybride du « mot du jour » : le mot est extrait de l'actu réelle et on
fige où il se cachait (titre/description + surface à surligner). Purement
additif (colonnes nullable, sans backfill, sans NOT NULL, sans drop) →
compatible expand-contract avec la DB partagée staging/prod.

- hybrid_field      : "title" | "description" (badge « caché dans le … »).
- hybrid_snippet    : texte exact à afficher (titre complet ou fenêtre de desc).
- hybrid_match      : surface exacte à surligner dans le snippet.
- hybrid_word_source: "hybrid" vs NULL/seed (idempotence + observabilité).
"""

import sqlalchemy as sa

from alembic import op

revision: str = "gh01_grille_hybrid_word"
down_revision: str | None = "mg01_merge_au01_rsvps"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    op.add_column(
        "grille_puzzles",
        sa.Column("hybrid_field", sa.Text(), nullable=True),
    )
    op.add_column(
        "grille_puzzles",
        sa.Column("hybrid_snippet", sa.Text(), nullable=True),
    )
    op.add_column(
        "grille_puzzles",
        sa.Column("hybrid_match", sa.Text(), nullable=True),
    )
    op.add_column(
        "grille_puzzles",
        sa.Column("hybrid_word_source", sa.String(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("grille_puzzles", "hybrid_word_source")
    op.drop_column("grille_puzzles", "hybrid_match")
    op.drop_column("grille_puzzles", "hybrid_snippet")
    op.drop_column("grille_puzzles", "hybrid_field")
