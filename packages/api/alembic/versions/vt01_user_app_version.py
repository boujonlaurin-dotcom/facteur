"""user app version tracking — app_version + app_version_updated_at on user_profiles.

Stores the last app version seen per user, updated on each session_start event.
Enables a version distribution dashboard without requiring dedicated device tables.
"""

import sqlalchemy as sa

from alembic import op

revision: str = "vt01_user_app_version"
down_revision: str | None = "23a3_custom_topic_fav_drop"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    op.add_column(
        "user_profiles",
        sa.Column("app_version", sa.String(length=20), nullable=True),
    )
    op.add_column(
        "user_profiles",
        sa.Column("app_version_updated_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index(
        "ix_user_profiles_app_version",
        "user_profiles",
        ["app_version"],
    )


def downgrade() -> None:
    op.drop_index("ix_user_profiles_app_version", table_name="user_profiles")
    op.drop_column("user_profiles", "app_version_updated_at")
    op.drop_column("user_profiles", "app_version")
