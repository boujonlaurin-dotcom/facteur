"""Daily purge of soft-deleted user accounts.

Hard-deletes `user_profiles` rows whose `deleted_at` is older than 30 days.
The `ON DELETE CASCADE` on `user_preferences`, `user_interests`,
`user_subtopics`, `user_letter_progress`, `user_personalization`,
`user_notification_preferences`, `user_topic_profile` and the `veille_*`
tables takes care of the dependent rows.

Tables without a FK (user_streaks, daily_digest, subscriptions, analytics…)
intentionally keep their rows: they only reference the user_id UUID and
contain no PII once the profile is gone, which is OK for anonymous
aggregate stats.
"""

from datetime import UTC, datetime, timedelta

import structlog
from sqlalchemy import delete

from app.database import safe_async_session
from app.models.user import UserProfile

logger = structlog.get_logger()

PURGE_AFTER_DAYS = 30


async def purge_deleted_users() -> dict:
    """Delete user_profiles soft-deleted more than PURGE_AFTER_DAYS ago.

    Returns a stats dict suitable for logging/tests:
        {"deleted_count": int, "cutoff": iso-timestamp}
    """
    cutoff = datetime.now(UTC) - timedelta(days=PURGE_AFTER_DAYS)
    async with safe_async_session() as session:
        result = await session.execute(
            delete(UserProfile).where(
                UserProfile.deleted_at.is_not(None),
                UserProfile.deleted_at < cutoff,
            )
        )
        await session.commit()
        deleted_count = result.rowcount or 0

    logger.info(
        "purge_deleted_users_completed",
        deleted_count=deleted_count,
        cutoff=cutoff.isoformat(),
    )
    return {"deleted_count": deleted_count, "cutoff": cutoff.isoformat()}
