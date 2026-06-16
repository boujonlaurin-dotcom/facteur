"""content deep recommendations — pré-calcul « Pas de recul » par article.

Table content-keyed : 1 ligne par article ouvert (``content_id``) avec
l'article de fond recommandé (``matched_content_id``, NULL = calculé sans
match). Alimente le rail « Pas de recul » du reader sans calcul LLM à la
volée (cf. story 27.1).

Additive (CREATE TABLE pur) → sûre en expand-contract sur la DB partagée
staging/prod : le backend prod (ancien code) ignore la table jusqu'au passage
hebdo. Migration idempotente (no-op si la table existe déjà).
"""

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID as PGUUID

from alembic import op

revision: str = "zz01_content_deep_reco"
down_revision: str | None = "gh01_grille_hybrid_word"
branch_labels: str | None = None
depends_on: str | None = None

_TABLE = "content_deep_recommendations"
_INDEX = "ix_content_deep_recommendations_matched_content_id"


def upgrade() -> None:
    bind = op.get_bind()
    if sa.inspect(bind).has_table(_TABLE):
        return
    op.create_table(
        _TABLE,
        sa.Column("content_id", PGUUID(as_uuid=True), nullable=False),
        sa.Column("matched_content_id", PGUUID(as_uuid=True), nullable=True),
        sa.Column("match_reason", sa.Text(), nullable=True),
        sa.Column(
            "computed_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["content_id"], ["contents.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["matched_content_id"], ["contents.id"], ondelete="SET NULL"
        ),
        sa.PrimaryKeyConstraint("content_id"),
    )
    op.create_index(_INDEX, _TABLE, ["matched_content_id"])


def downgrade() -> None:
    bind = op.get_bind()
    if not sa.inspect(bind).has_table(_TABLE):
        return
    op.drop_index(_INDEX, table_name=_TABLE)
    op.drop_table(_TABLE)
