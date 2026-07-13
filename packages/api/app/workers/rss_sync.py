"""Worker de synchronisation RSS."""

import structlog

from app.database import safe_async_session
from app.services.sync_service import SyncService

logger = structlog.get_logger()


async def sync_all_sources() -> dict:
    """Fonction wrapper pour le scheduler.

    Returns:
        Dictionnaire de résultats {success, failed, total_new}
    """
    logger.info("Executing periodic RSS sync job")

    async with safe_async_session() as session:
        service = SyncService(session, session_maker=safe_async_session)
        try:
            return await service.sync_all_sources()
        finally:
            # Libère la connexion Supavisor même si SyncService a entamé une
            # tx implicite sur la session outer (sinon → idle in transaction).
            try:
                await session.rollback()
            except Exception:
                logger.warning("rss_sync outer rollback failed", exc_info=True)
            await service.close()


async def seed_source(source_id: str, *, max_items: int = 10) -> int:
    """Sème synchroniquement une tranche bornée de contenus pour une source.

    Story 12.2 (T1d) : appelé par ``add_source`` sous un time-box strict pour
    remplir la tournée immédiatement. Retourne le nombre de contents insérés
    (0 si source absente ou fetch en échec). Ne lève pas — l'appelant retombe
    en background-only via le filet ``sync_source``.
    """
    async with safe_async_session() as session:
        service = SyncService(session, session_maker=safe_async_session)
        try:
            from uuid import UUID

            from sqlalchemy import select

            from app.models.source import Source

            result = await session.execute(
                select(Source).where(Source.id == UUID(source_id))
            )
            source = result.scalar_one_or_none()
            if not source:
                return 0
            # Détache pour que les attributs restent lisibles pendant les
            # sessions courtes de _save_content.
            session.expunge(source)
            return await service.seed_recent_content(source, max_items=max_items)
        finally:
            try:
                await session.rollback()
            except Exception:
                logger.warning("seed_source outer rollback failed", exc_info=True)
            await service.close()


async def sync_source(source_id: str) -> bool:
    """Synchronise une source spécifique par son ID.

    Args:
        source_id: UUID de la source

    Returns:
        True si succès, False sinon
    """
    logger.info("Executing manual RSS sync for source", source_id=source_id)

    async with safe_async_session() as session:
        service = SyncService(session, session_maker=safe_async_session)
        try:
            # Récupérer la source
            from uuid import UUID

            from sqlalchemy import select

            from app.models.source import Source

            result = await session.execute(
                select(Source).where(Source.id == UUID(source_id))
            )
            source = result.scalar_one_or_none()

            if not source:
                logger.error("Source not found", source_id=source_id)
                return False

            await service.process_source(source)
            return True
        except Exception as e:
            logger.error(
                "Error in sync_source worker", source_id=source_id, error=str(e)
            )
            return False
        finally:
            try:
                await session.rollback()
            except Exception:
                logger.warning("sync_source outer rollback failed", exc_info=True)
            await service.close()
