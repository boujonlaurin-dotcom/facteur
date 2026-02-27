"""Worker de synchronisation RSS."""

import structlog

from app.database import async_session_maker
from app.services.sync_service import SyncService

logger = structlog.get_logger()


async def sync_all_sources() -> dict:
    """Fonction wrapper pour le scheduler.

    Returns:
        Dictionnaire de résultats {success, failed, total_new}
    """
    logger.info("Executing periodic RSS sync job")

    async with async_session_maker() as session:
        service = SyncService(session, session_maker=async_session_maker)
        try:
            return await service.sync_all_sources()
        finally:
            await service.close()


async def sync_source(source_id: str) -> bool:
    """Synchronise une source spécifique par son ID.

    Args:
        source_id: UUID de la source

    Returns:
        True si succès, False sinon
    """
    logger.info("Executing manual RSS sync for source", source_id=source_id)

    async with async_session_maker() as session:
        service = SyncService(session, session_maker=async_session_maker)
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
            await service.close()
