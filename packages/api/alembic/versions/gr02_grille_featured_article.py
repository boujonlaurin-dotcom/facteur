"""grille — article réel accroché au reveal (auto-matching)

Migration **additive** : ajoute à `grille_puzzles` un snapshot figé de l'article
de la tournée qui matche le mot du jour (peuplé best-effort par le job digest).
Toutes les colonnes sont **nullable** (aucun match → reveal retombe sur
`pourquoi`). FK `featured_content_id → contents.id ON DELETE SET NULL` pour que
la purge d'un article ne casse jamais une grille (l'extrait reste figé en base).

Head précédent : dg02_digest_serene_idx. Après : 1 seul head (gr02).
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "gr02_grille_featured_article"
down_revision: str | None = "dg02_digest_serene_idx"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    op.add_column(
        "grille_puzzles",
        sa.Column("featured_content_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.add_column(
        "grille_puzzles", sa.Column("featured_title", sa.Text(), nullable=True)
    )
    op.add_column(
        "grille_puzzles", sa.Column("featured_excerpt", sa.Text(), nullable=True)
    )
    op.add_column(
        "grille_puzzles", sa.Column("featured_url", sa.Text(), nullable=True)
    )
    op.add_column(
        "grille_puzzles", sa.Column("featured_source", sa.Text(), nullable=True)
    )
    op.add_column(
        "grille_puzzles",
        sa.Column("featured_matched_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_foreign_key(
        "fk_grille_puzzles_featured_content",
        "grille_puzzles",
        "contents",
        ["featured_content_id"],
        ["id"],
        ondelete="SET NULL",
    )


def downgrade() -> None:
    op.drop_constraint(
        "fk_grille_puzzles_featured_content",
        "grille_puzzles",
        type_="foreignkey",
    )
    op.drop_column("grille_puzzles", "featured_matched_at")
    op.drop_column("grille_puzzles", "featured_source")
    op.drop_column("grille_puzzles", "featured_url")
    op.drop_column("grille_puzzles", "featured_excerpt")
    op.drop_column("grille_puzzles", "featured_title")
    op.drop_column("grille_puzzles", "featured_content_id")
