from fastapi import APIRouter, BackgroundTasks, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.services.classification_queue_service import ClassificationQueueService
from app.workers.rss_sync import sync_all_sources

router = APIRouter()


@router.post("/sync", status_code=status.HTTP_200_OK)
async def trigger_sync(
    # Ajouter ici une protection admin si nécessaire (Depends(get_current_admin_user))
):
    """Déclenche manuellement la synchronisation RSS de toutes les sources."""
    results = await sync_all_sources()
    return {"message": "Sync completed", "results": results}


@router.post("/briefing", status_code=status.HTTP_200_OK)
async def trigger_daily_briefing(background_tasks: BackgroundTasks):
    """Déclenche manuellement la génération du Top 3 Quotidien."""
    # On lance en tâche de fond pour ne pas bloquer, mais pour le test d'intégration
    # il faudra poller ou checker les logs.
    # Pour le dev, on peut aussi l'await si on veut le retour direct
    # Ici on choisit d'await pour voir le résultat dans la réponse du test
    from app.workers.top3_job import generate_daily_top3_job

    await generate_daily_top3_job(trigger_manual=True)
    return {"message": "Daily Top 3 generation completed"}


@router.get("/admin/queue-stats", status_code=status.HTTP_200_OK)
async def get_queue_stats(
    session: AsyncSession = Depends(get_db),
):
    """Récupère les statistiques de la file de classification ML.

    Returns:
        Statistiques de la queue: pending, processing, completed, failed, etc.
    """
    service = ClassificationQueueService(session)
    stats = await service.get_queue_stats()
    return {"message": "Queue statistics", "stats": stats}
