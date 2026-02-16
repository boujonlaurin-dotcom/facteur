"""Worker de nettoyage du storage RSS."""

import structlog
from datetime import datetime, timedelta, timezone

from sqlalchemy import delete, select, func, exists

from app.config import get_settings
from app.database import async_session_maker
from app.models.content import Content, UserContentStatus

logger = structlog.get_logger()
settings = get_settings()


async def cleanup_old_articles() -> dict:
    """Purge les articles RSS plus anciens que rss_retention_days.

    Exclut les articles bookmarkés (is_saved=True) pour préserver les favoris users.

    Returns:
        Dict avec statistiques: {deleted_count, retention_days, preserved_bookmarks}
    """
    retention_days = settings.rss_retention_days
    cutoff_date = datetime.now(timezone.utc) - timedelta(days=retention_days)

    logger.info(
        "storage_cleanup_started",
        retention_days=retention_days,
        cutoff_date=cutoff_date.isoformat(),
    )

    async with async_session_maker() as session:
        try:
            # Subquery: articles bookmarkés (à préserver)
            bookmarked_subquery = (
                select(UserContentStatus.content_id)
                .where(UserContentStatus.is_saved == True)
            )

            # Count avant purge (pour logging)
            count_result = await session.execute(
                select(func.count()).select_from(Content).where(
                    Content.published_at < cutoff_date,
                    ~Content.id.in_(bookmarked_subquery)  # Exclure bookmarks
                )
            )
            to_delete = count_result.scalar_one()

            # Count bookmarks préservés
            preserved_result = await session.execute(
                select(func.count()).select_from(Content).where(
                    Content.published_at < cutoff_date,
                    Content.id.in_(bookmarked_subquery)
                )
            )
            preserved_bookmarks = preserved_result.scalar_one()

            if to_delete == 0:
                logger.info(
                    "storage_cleanup_skipped",
                    reason="no_old_articles",
                    preserved_bookmarks=preserved_bookmarks,
                )
                return {
                    "deleted_count": 0,
                    "retention_days": retention_days,
                    "preserved_bookmarks": preserved_bookmarks,
                }

            # Delete - exclut les bookmarks, FK CASCADE gèrent user_content_status, daily_top3, classification_queue
            result = await session.execute(
                delete(Content).where(
                    Content.published_at < cutoff_date,
                    ~Content.id.in_(bookmarked_subquery)
                )
            )
            deleted_count = result.rowcount

            await session.commit()

            logger.info(
                "storage_cleanup_completed",
                deleted_count=deleted_count,
                preserved_bookmarks=preserved_bookmarks,
                retention_days=retention_days,
                cutoff_date=cutoff_date.isoformat(),
            )

            return {
                "deleted_count": deleted_count,
                "retention_days": retention_days,
                "preserved_bookmarks": preserved_bookmarks,
            }

        except Exception as e:
            await session.rollback()
            logger.error(
                "storage_cleanup_failed",
                error=str(e),
                retention_days=retention_days,
                exc_info=True,
            )
            raise
