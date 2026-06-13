"""Worker de nettoyage du storage RSS."""

from datetime import UTC, datetime, timedelta
from uuid import UUID

import structlog
from sqlalchemy import delete, exists, func, not_, select

from app.config import get_settings
from app.database import safe_async_session
from app.models.classification_queue import ClassificationQueue
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

# Rétention des lignes terminées de classification_queue. Doit rester très
# au-dessus de la fenêtre de requeue_for_reclassification (48 h) : une ligne
# purgée trop tôt serait ré-enqueueable et re-classifiée pour rien.
CLASSIFICATION_QUEUE_RETENTION_DAYS = 30


async def purge_finished_classification_queue() -> int:
    """Purge les lignes completed/failed/cancelled de classification_queue.

    La file est append-only côté terminé : sans purge, les lignes (et leurs
    index) croissent en O(articles) pour toujours. Best-effort : un échec ne
    doit pas faire échouer le cleanup des articles.

    Returns:
        Nombre de lignes supprimées (0 en cas d'erreur).
    """
    cutoff = datetime.now(UTC) - timedelta(days=CLASSIFICATION_QUEUE_RETENTION_DAYS)
    try:
        async with safe_async_session() as session:
            result = await session.execute(
                delete(ClassificationQueue).where(
                    ClassificationQueue.status.in_(
                        ["completed", "failed", "cancelled"]
                    ),
                    ClassificationQueue.updated_at < cutoff,
                )
            )
            await session.commit()
            deleted = result.rowcount
            logger.info(
                "classification_queue_purged",
                deleted_count=deleted,
                retention_days=CLASSIFICATION_QUEUE_RETENTION_DAYS,
            )
            return deleted
    except Exception as e:
        logger.error("classification_queue_purge_failed", error=str(e))
        return 0


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

    # Purge des lignes terminées de classification_queue, co-localisée ici
    # (même fenêtre de maintenance 03:00, pas de slot cron supplémentaire).
    # Distincte du CASCADE déclenché par le DELETE Content plus bas : le CASCADE
    # ne nettoie que les lignes liées aux articles supprimés, pas celles dont
    # le Content a survécu (bookmark/deep/digest-ref) mais dont la file est
    # terminée. Best-effort : un échec ne bloque pas le cleanup des articles.
    purged_queue_rows = await purge_finished_classification_queue()

    async with safe_async_session() as session:
        try:
            # NOT EXISTS plutôt que NOT IN (subquery) : permet à Postgres
            # d'utiliser un anti-join indexé (ix_user_content_status_content_id
            # ajouté en parallèle), au lieu de matérialiser la subquery puis
            # filtrer ligne par ligne.
            bookmarked_exists = exists().where(
                UserContentStatus.content_id == Content.id,
                UserContentStatus.is_saved,
            )
            # Source deep : corrélée sur source_id (PK Source → très rapide).
            deep_source_exists = exists().where(
                Source.id == Content.source_id,
                Source.source_tier == "deep",
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
                not_(bookmarked_exists),
                not_(deep_source_exists),
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
                    bookmarked_exists,
                )
            )
            preserved_bookmarks = preserved_result.scalar_one()

            # Count deep source articles préservés
            preserved_deep_result = await session.execute(
                select(func.count())
                .select_from(Content)
                .where(
                    Content.published_at < cutoff_date,
                    deep_source_exists,
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
                    "purged_queue_rows": purged_queue_rows,
                }

            # Delete - réutilise les mêmes conditions que le count. FK CASCADE
            # gère user_content_status, classification_queue.
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
                "purged_queue_rows": purged_queue_rows,
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
