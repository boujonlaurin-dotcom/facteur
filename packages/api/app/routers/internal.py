from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.workers.rss_sync import sync_all_sources

router = APIRouter()

@router.post("/sync", status_code=status.HTTP_200_OK)
async def trigger_sync(
    # Ajouter ici une protection admin si nécessaire (Depends(get_current_admin_user))
):
    """Déclenche manuellement la synchronisation RSS de toutes les sources."""
    results = await sync_all_sources()
    return {"message": "Sync completed", "results": results}
