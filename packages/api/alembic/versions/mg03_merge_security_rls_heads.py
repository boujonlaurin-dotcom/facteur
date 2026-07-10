"""merge security RLS with current PR Alembic heads.

No schema changes. This revision reconciles the RLS lockdown branch with the
content deep recommendation branch so `alembic upgrade head` has a single
target.
"""

revision: str = "mg03_merge_security_rls_heads"
down_revision: tuple[str, ...] = (
    "sec01_lock_down_public_rls",
    "zz01_content_deep_reco",
)
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
