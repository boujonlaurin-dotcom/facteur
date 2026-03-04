"""migrate_taxonomy_slugs

Revision ID: e12a0001
Revises: c134526be6cd
Create Date: 2026-03-04 12:00:00.000000

Epic 12: Align user preference slugs with ML VALID_TOPIC_SLUGS.
Migrates old invented slugs (crypto, social-justice, etc.) to valid ML slugs
in user_subtopics and user_personalization.muted_topics.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'e12a0001'
down_revision: Union[str, Sequence[str], None] = 'c134526be6cd'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


# Old invented slugs → valid ML topic slugs
SLUG_MIGRATION_MAP: dict[str, str] = {
    "crypto": "finance",
    "social-justice": "justice",
    "housing": "realestate",
    "energy-transition": "energy",
    "macro": "economy",
    "media-critics": "media",
    "elections": "politics",
    "institutions": "politics",
    "fundamental-research": "science",
    "applied-science": "science",
    "middle-east": "middleeast",
    "physics": "science",
    "biology": "science",
    "arts": "art",
    "french-politics": "politics",
    "labor": "work",
    "macroeconomics": "economy",
}


def upgrade() -> None:
    """Migrate old taxonomy slugs to valid ML slugs."""
    conn = op.get_bind()

    # --- 1. Migrate user_subtopics.topic_slug ---
    total_subtopics_updated = 0
    for old_slug, new_slug in SLUG_MIGRATION_MAP.items():
        result = conn.execute(
            sa.text(
                "UPDATE user_subtopics SET topic_slug = :new_slug "
                "WHERE topic_slug = :old_slug"
            ).bindparams(new_slug=new_slug, old_slug=old_slug)
        )
        total_subtopics_updated += result.rowcount

    # Deduplicate: if a user now has 2 rows with the same topic_slug
    # (e.g. elections→politics AND institutions→politics), keep the oldest
    dedup_result = conn.execute(
        sa.text(
            "DELETE FROM user_subtopics "
            "WHERE id IN ("
            "  SELECT id FROM ("
            "    SELECT id, ROW_NUMBER() OVER ("
            "      PARTITION BY user_id, topic_slug ORDER BY created_at ASC"
            "    ) AS rn"
            "    FROM user_subtopics"
            "  ) ranked WHERE rn > 1"
            ")"
        )
    )
    duplicates_removed = dedup_result.rowcount

    print(f"[Epic 12] user_subtopics: {total_subtopics_updated} slugs updated, "
          f"{duplicates_removed} duplicates removed")

    # --- 2. Migrate user_personalization.muted_topics ---
    # Read all rows, remap slugs in the array, deduplicate, update
    rows = conn.execute(
        sa.text("SELECT user_id, muted_topics FROM user_personalization "
                "WHERE muted_topics IS NOT NULL AND array_length(muted_topics, 1) > 0")
    ).fetchall()

    muted_updated = 0
    for row in rows:
        user_id = row[0]
        old_topics = row[1]
        new_topics: list[str] = []
        changed = False

        for slug in old_topics:
            mapped = SLUG_MIGRATION_MAP.get(slug, slug)
            if mapped != slug:
                changed = True
            if mapped not in new_topics:
                new_topics.append(mapped)

        if changed:
            conn.execute(
                sa.text(
                    "UPDATE user_personalization SET muted_topics = :topics "
                    "WHERE user_id = :uid"
                ).bindparams(topics=new_topics, uid=user_id)
            )
            muted_updated += 1

    print(f"[Epic 12] user_personalization.muted_topics: {muted_updated} rows updated "
          f"(out of {len(rows)} with muted topics)")


def downgrade() -> None:
    """Best-effort reverse mapping. Merges (many→one) cannot be perfectly reversed.
    NOTE: muted_topics in user_personalization are NOT reverted (manual DB restore required)."""
    conn = op.get_bind()

    # Reverse the 1-to-1 mappings only (skip many-to-one merges)
    REVERSE_MAP: dict[str, str] = {
        "finance": "crypto",
        "justice": "social-justice",
        "realestate": "housing",
        "energy": "energy-transition",
        "media": "media-critics",
        "middleeast": "middle-east",
        "art": "arts",
        "work": "labor",
    }

    for new_slug, old_slug in REVERSE_MAP.items():
        conn.execute(
            sa.text(
                "UPDATE user_subtopics SET topic_slug = :old_slug "
                "WHERE topic_slug = :new_slug"
            ).bindparams(old_slug=old_slug, new_slug=new_slug)
        )

    # Note: many-to-one mappings (elections+institutions→politics,
    # fundamental-research+applied-science+physics+biology→science,
    # macro+macroeconomics→economy) are not reversible.
    print("[Epic 12] downgrade: reversed 1-to-1 mappings. "
          "Many-to-one merges (politics, science, economy) not reversed.")
