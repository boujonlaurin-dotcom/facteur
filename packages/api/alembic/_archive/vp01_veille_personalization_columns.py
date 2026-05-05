"""veille personalization columns + notif veille toggle

Revision ID: vp01
Revises: ls01
Create Date: 2026-05-03

Pose les fondations DB pour la refonte V1 de la veille (PR A) :
- 4 colonnes nullables sur `veille_configs` pour capturer purpose/brief/preset
  (PR B câblera la persistance via le router /config).
- Toggle `notif_veille_enabled` sur `user_notification_preferences` pour la
  modal opt-in notif veille (PR C).
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "vp01"
down_revision: str | Sequence[str] | None = "ls01"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "veille_configs",
        sa.Column("purpose", sa.Text(), nullable=True),
    )
    op.add_column(
        "veille_configs",
        sa.Column("purpose_other", sa.Text(), nullable=True),
    )
    op.add_column(
        "veille_configs",
        sa.Column("editorial_brief", sa.Text(), nullable=True),
    )
    op.add_column(
        "veille_configs",
        sa.Column("preset_id", sa.Text(), nullable=True),
    )
    op.add_column(
        "user_notification_preferences",
        sa.Column(
            "notif_veille_enabled",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
    )


def downgrade() -> None:
    op.drop_column("user_notification_preferences", "notif_veille_enabled")
    op.drop_column("veille_configs", "preset_id")
    op.drop_column("veille_configs", "editorial_brief")
    op.drop_column("veille_configs", "purpose_other")
    op.drop_column("veille_configs", "purpose")
