"""Worker de nettoyage du storage RSS."""

from datetime import UTC, datetime, timedelta
from uuid import UUID

import structlog
from sqlalchemy import delete, func, select

from app.config import get_settings
from app.database import async_session_maker
from app.models.content import Content, UserContentStatus
from app.models.daily_digest import DailyDigest
from app.models.source import Source
from app.services.digest_content_refs import extract_content_ids

logger = structlog.get_logger()
settings = get_settings()

# Any Content referenced by a digest generated in the last N days must be
# preserved — otherwise rendering that digest crashes with
# editorial_article_not_found and triggers a 503 for the owning user.
# 90 days covers the longest realistic streak fallback window.
DIGEST_REFERENCE_PROTECTION_DAYS = 90


async def _collect_referenced_content_ids(session) -> set[UUID]:
    """Return every content_id referenced by a digest from the last 90 days.

    Walks all three JSONB layouts (flat_v1, topics_v1, editorial_v1) in
    Python so we don't have to maintain three parallel JSONB queries. In
    production the digest table is small (~O(users × days × variants)), so
    pulling the raw rows is cheap.
    """
    cutoff = datetime.now(UTC) - timedelta(days=DIGEST_REFERENCE_PROTECTION_DAYS)
    stmt = select(DailyDigest.items, DailyDigest.format_version).where(
        DailyDigest.generated_at >= cutoff
    )
    result = await session.execute(stmt)
    referenced: set[UUID] = set()
    for items, format_version in result.all():
        referenced |= extract_content_ids(items, format_version)
    return referenced


async def cleanup_old_articles() -> dict:
    """Purge les articles RSS plus anciens que rss_retention_days.

    Exclut les articles bookmarkés (is_saved=True) pour préserver les favoris users.

    Returns:
        Dict avec statistiques: {deleted_count, retention_days, preserved_bookmarks}
    """
    retention_days = settings.rss_retention_days
    cutoff_date = datetime.now(UTC) - timedelta(days=retention_days)

    logger.info(
        "storage_cleanup_started",
        retention_days=retention_days,
        cutoff_date=cutoff_date.isoformat(),
    )

    async with async_session_maker() as session:
        try:
            # Subquery: articles bookmarkés (à préserver)
            bookmarked_subquery = select(UserContentStatus.content_id).where(
                UserContentStatus.is_saved
            )

            # Subquery: articles de sources deep (à préserver — Story 10.22)
            deep_source_subquery = (
                select(Content.id)
                .join(Source, Content.source_id == Source.id)
                .where(Source.source_tier == "deep")
            )

            # Set: content_ids référencés par un digest des 90 derniers jours.
            # Supprimer l'un d'entre eux casserait le rendu du digest (l'article
            # référencé n'existe plus côté Content) → 503 pour l'owner.
            referenced_ids = await _collect_referenced_content_ids(session)
            referenced_list = list(referenced_ids)
            preserved_digest_refs = len(referenced_list)

            # Conditions communes entre le count et le delete :
            # exclut bookmarks, deep sources et contents référencés par un
            # digest récent.
            common_conditions = [
                Content.published_at < cutoff_date,
                ~Content.id.in_(bookmarked_subquery),
                ~Content.id.in_(deep_source_subquery),
            ]
            if referenced_list:
                common_conditions.append(~Content.id.in_(referenced_list))

            # Count avant purge (pour logging)
            count_result = await session.execute(
                select(func.count()).select_from(Content).where(*common_conditions)
            )
            to_delete = count_result.scalar_one()

            # Count bookmarks préservés
            preserved_result = await session.execute(
                select(func.count())
                .select_from(Content)
                .where(
                    Content.published_at < cutoff_date,
                    Content.id.in_(bookmarked_subquery),
                )
            )
            preserved_bookmarks = preserved_result.scalar_one()

            # Count deep source articles préservés
            preserved_deep_result = await session.execute(
                select(func.count())
                .select_from(Content)
                .where(
                    Content.published_at < cutoff_date,
                    Content.id.in_(deep_source_subquery),
                )
            )
            preserved_deep = preserved_deep_result.scalar_one()

            if to_delete == 0:
                logger.info(
                    "storage_cleanup_skipped",
                    reason="no_old_articles",
                    preserved_bookmarks=preserved_bookmarks,
                    preserved_deep=preserved_deep,
                    preserved_digest_refs=preserved_digest_refs,
                )
                return {
                    "deleted_count": 0,
                    "retention_days": retention_days,
                    "preserved_bookmarks": preserved_bookmarks,
                    "preserved_deep": preserved_deep,
                    "preserved_digest_refs": preserved_digest_refs,
                }

            # Delete - réutilise les mêmes conditions que le count. FK CASCADE
            # gère user_content_status, daily_top3, classification_queue.
            result = await session.execute(delete(Content).where(*common_conditions))
            deleted_count = result.rowcount

            await session.commit()

            logger.info(
                "storage_cleanup_completed",
                deleted_count=deleted_count,
                preserved_bookmarks=preserved_bookmarks,
                preserved_deep=preserved_deep,
                preserved_digest_refs=preserved_digest_refs,
                retention_days=retention_days,
                cutoff_date=cutoff_date.isoformat(),
            )

            return {
                "deleted_count": deleted_count,
                "retention_days": retention_days,
                "preserved_bookmarks": preserved_bookmarks,
                "preserved_deep": preserved_deep,
                "preserved_digest_refs": preserved_digest_refs,
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
