from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user_id
from app.models.enums import ContentStatus
from app.schemas.content import ContentStatusUpdate, HideContentRequest
from app.services.content_service import ContentService

router = APIRouter()

@router.post("/{content_id}/status", status_code=status.HTTP_200_OK)
async def update_content_status(
    content_id: UUID,
    update_data: ContentStatusUpdate,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """
    Met à jour le statut de consommation d'un contenu (Lu, Vu).
    
    Trigger: 
    - Au scroll (SEEN)
    - Au retour de la WebView (CONSUMED + time_spent)
    """
    service = ContentService(db)
    user_uuid = UUID(current_user_id)
    
    updated_status = await service.update_content_status(
        user_id=user_uuid,
        content_id=content_id,
        update_data=update_data
    )
    
    await db.commit()
    return {"status": "ok", "current_status": updated_status.status}


@router.post("/{content_id}/save", status_code=status.HTTP_200_OK)
async def save_content(
    content_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Sauvegarde un contenu pour plus tard."""
    service = ContentService(db)
    user_uuid = UUID(current_user_id)

    updated_status = await service.set_save_status(
        user_id=user_uuid,
        content_id=content_id,
        is_saved=True
    )
    
    await db.commit()
    return {"status": "ok", "is_saved": True}


@router.delete("/{content_id}/save", status_code=status.HTTP_200_OK)
async def unsave_content(
    content_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Retire un contenu des sauvegardés."""
    service = ContentService(db)
    user_uuid = UUID(current_user_id)

    updated_status = await service.set_save_status(
        user_id=user_uuid,
        content_id=content_id,
        is_saved=False
    )
    
    await db.commit()
    return {"status": "ok", "is_saved": False}


@router.post("/{content_id}/hide", status_code=status.HTTP_200_OK)
async def hide_content(
    content_id: UUID,
    request: HideContentRequest,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Masque un contenu (pas intéressé)."""
    service = ContentService(db)
    user_uuid = UUID(current_user_id)

    updated_status = await service.set_hide_status(
        user_id=user_uuid,
        content_id=content_id,
        is_hidden=True,
        reason=request.reason
    )
    
    await db.commit()
    return {"status": "ok", "is_hidden": True, "reason": request.reason}


@router.get("/{content_id}/perspectives", status_code=status.HTTP_200_OK)
async def get_perspectives(
    content_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """
    Récupère des perspectives alternatives sur un contenu via Google News.
    MVP: Recherche live basée sur les mots-clés du titre.
    """
    from app.models.content import Content
    from app.services.perspective_service import PerspectiveService
    from sqlalchemy import select
    
    # Get the content title
    result = await db.execute(select(Content).where(Content.id == content_id))
    content = result.scalars().first()
    
    if not content:
        raise HTTPException(status_code=404, detail="Content not found")
    
    # Search perspectives with exclusions
    service = PerspectiveService()
    keywords = service.extract_keywords(content.title)
    
    if not keywords:
        return {"content_id": str(content_id), "perspectives": [], "keywords": []}
    
    perspectives = await service.search_perspectives(
        keywords, 
        exclude_url=content.url, 
        exclude_title=content.title
    )
    
    # Calculate bias distribution
    bias_distribution = {"left": 0, "center-left": 0, "center": 0, "center-right": 0, "right": 0, "unknown": 0}
    for p in perspectives:
        bias_distribution[p.bias_stance] = bias_distribution.get(p.bias_stance, 0) + 1
    
    return {
        "content_id": str(content_id),
        "keywords": keywords,
        "perspectives": [
            {
                "title": p.title,
                "url": p.url,
                "source_name": p.source_name,
                "source_domain": p.source_domain,
                "bias_stance": p.bias_stance,
                "published_at": p.published_at,
            }
            for p in perspectives
        ],
        "bias_distribution": bias_distribution
    }
