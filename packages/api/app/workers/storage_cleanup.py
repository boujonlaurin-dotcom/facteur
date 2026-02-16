"""Worker de nettoyage du storage RSS."""

import structlog
from datetime import datetime, timedelta, timezone

from sqlalchemy import delete, select, func

from app.config import get_settings
from app.database import async_session_maker
from app.models.content import Content

logger = structlog.get_logger()
settings = get_settings()


async def cleanup_old_articles() -> dict:
    """Purge les articles RSS plus anciens que rss_retention_days.

    Returns:
        Dict avec statistiques: {deleted_count, retention_days}
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
            # Count avant purge (pour logging)
            count_result = await session.execute(
                select(func.count()).select_from(Content).where(
                    Content.published_at < cutoff_date
                )
            )
            to_delete = count_result.scalar_one()

            if to_delete == 0:
                logger.info("storage_cleanup_skipped", reason="no_old_articles")
                return {"deleted_count": 0, "retention_days": retention_days}

            # Delete - les FK CASCADE gèrent user_content_status, daily_top3, classification_queue
            result = await session.execute(
                delete(Content).where(Content.published_at < cutoff_date)
            )
            deleted_count = result.rowcount

            await session.commit()

            logger.info(
                "storage_cleanup_completed",
                deleted_count=deleted_count,
                retention_days=retention_days,
                cutoff_date=cutoff_date.isoformat(),
            )

            return {
                "deleted_count": deleted_count,
                "retention_days": retention_days,
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
