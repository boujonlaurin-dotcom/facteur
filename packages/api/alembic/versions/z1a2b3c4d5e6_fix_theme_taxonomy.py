"""fix_theme_taxonomy

Revision ID: z1a2b3c4d5e6
Revises: 531d5a43b511
Create Date: 2026-01-29 10:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'z1a2b3c4d5e6'
down_revision: Union[str, Sequence[str], None] = '531d5a43b511'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Convert French theme labels to normalized slugs."""
    # Mapping from French labels to normalized slugs
    TAXONOMY_MAP = {
        "Tech & Futur": "tech",
        "Société & Climat": "society",
        "Environnement": "environment",
        "Économie": "economy",
        "Politique": "politics",
        "Culture": "culture",
        "Science": "science",
        "International": "international",
        # Legacy mappings (if any)
        "culture_ideas": "culture",
        "geopolitics": "international",
        "society_climate": "society",
    }
    
    # Update existing sources with French labels
    for old_label, new_slug in TAXONOMY_MAP.items():
        op.execute(f"UPDATE sources SET theme = '{new_slug}' WHERE theme = '{old_label}'")
    
    # Log the migration
    op.execute("SELECT COUNT(*) FROM sources WHERE theme IN ('tech', 'society', 'environment', 'economy', 'politics', 'culture', 'science', 'international')")


def downgrade() -> None:
    """Revert slugs back to French labels (if needed)."""
    # Reverse mapping
    REVERSE_MAP = {
        "tech": "Tech & Futur",
        "society": "Société & Climat",
        "environment": "Environnement",
        "economy": "Économie",
        "politics": "Politique",
        "culture": "Culture",
        "science": "Science",
        "international": "International",
    }
    
    # Revert to French labels
    for slug, label in REVERSE_MAP.items():
        op.execute(f"UPDATE sources SET theme = '{label}' WHERE theme = '{slug}'")
