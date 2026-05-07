"""soft delete user profiles — deleted_at + email_hash + index.

App Store 5.1.1(v) + Play Store account deletion compliance. The DELETE
/api/users/me endpoint sets `deleted_at` and stores a SHA256 hash of the
email captured from auth.users; a daily cron purges rows older than 30
days (cascading to user_preferences/interests/subtopics/etc.).
"""

import sqlalchemy as sa

from alembic import op

revision: str = "sd01_soft_delete_user_profiles"
down_revision: str | None = "00000_baseline"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    op.add_column(
        "user_profiles",
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "user_profiles",
        sa.Column("email_hash", sa.String(length=64), nullable=True),
    )
    op.create_index(
        "ix_user_profiles_deleted_at",
        "user_profiles",
        ["deleted_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_user_profiles_deleted_at", table_name="user_profiles")
    op.drop_column("user_profiles", "email_hash")
    op.drop_column("user_profiles", "deleted_at")
