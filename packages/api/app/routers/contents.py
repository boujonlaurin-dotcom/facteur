import asyncio
from datetime import UTC, datetime
from uuid import UUID

import structlog
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user_id
from app.models.content import Content
from app.models.enums import ContentType
from app.schemas.collection import SaveContentRequest
from app.schemas.content import (
    ContentDetailResponse,
    ContentStatusUpdate,
    HideContentRequest,
    NoteResponse,
    NoteUpsertRequest,
)
from app.services.collection_service import CollectionService
from app.services.content_extractor import ContentExtractor
from app.services.content_service import ContentService

logger = structlog.get_logger()

router = APIRouter()


@router.get(
    "/{content_id}",
    status_code=status.HTTP_200_OK,
    response_model=ContentDetailResponse,
)
async def get_content_detail(
    content_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """
    Récupère le détail d'un contenu.
    Enrichit le contenu on-demand via trafilatura si html_content manquant.
    """
    service = ContentService(db)
    user_uuid = UUID(current_user_id)

    content_data = await service.get_content_detail(content_id, user_uuid)
    if not content_data:
        raise HTTPException(status_code=404, detail="Contenu non trouvé")

    # On-demand enrichment: try to get full content for articles
    if content_data.get("content_type") == ContentType.ARTICLE:
        quality = content_data.get("content_quality")
        extractor = ContentExtractor(download_timeout=10)

        # Compute quality from existing content if not yet done
        if not quality and (
            content_data.get("html_content") or content_data.get("description")
        ):
            quality = extractor.compute_quality_for_existing(
                content_data.get("html_content"), content_data.get("description")
            )
            content_data["content_quality"] = quality

        # Try trafilatura if content is not full quality
        # AND no recent extraction attempt (cooldown 6h to prevent retry storms)
        attempted_at = content_data.get("extraction_attempted_at")
        cooldown_expired = (
            attempted_at is None
            or (datetime.now(UTC) - attempted_at).total_seconds() > 6 * 3600
        )

        if quality != "full" and cooldown_expired:
            try:
                result = await asyncio.wait_for(
                    asyncio.get_event_loop().run_in_executor(
                        None, extractor.extract, content_data["url"]
                    ),
                    timeout=15.0,
                )

                # Persist enrichment to DB (single commit)
                stmt = select(Content).where(Content.id == content_id)
                db_content = await db.scalar(stmt)
                if db_content:
                    db_content.extraction_attempted_at = datetime.now(UTC)
                    if result.html_content:
                        content_data["html_content"] = result.html_content
                        content_data["content_quality"] = result.content_quality
                        db_content.html_content = result.html_content
                        db_content.content_quality = result.content_quality
                        if (
                            result.reading_time_seconds
                            and not db_content.duration_seconds
                        ):
                            db_content.duration_seconds = result.reading_time_seconds
                            content_data["duration_seconds"] = (
                                result.reading_time_seconds
                            )
                    elif not db_content.content_quality:
                        db_content.content_quality = quality or "none"
                    await db.commit()

            except Exception:
                # Mark attempt even on failure to prevent retry storm
                try:
                    stmt = select(Content).where(Content.id == content_id)
                    db_content = await db.scalar(stmt)
                    if db_content:
                        db_content.extraction_attempted_at = datetime.now(UTC)
                        if not db_content.content_quality:
                            db_content.content_quality = quality or "none"
                        await db.commit()
                except Exception:
                    pass  # Don't fail the request over persistence
                logger.exception(
                    "on_demand_enrichment_failed",
                    content_id=str(content_id),
                )

    return content_data


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
        user_id=user_uuid, content_id=content_id, update_data=update_data
    )

    await db.commit()
    return {"status": "ok", "current_status": updated_status.status}


@router.post("/{content_id}/save", status_code=status.HTTP_200_OK)
async def save_content(
    content_id: UUID,
    data: SaveContentRequest | None = None,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Sauvegarde un contenu pour plus tard, optionnellement dans des collections."""
    service = ContentService(db)
    user_uuid = UUID(current_user_id)

    await service.set_save_status(
        user_id=user_uuid, content_id=content_id, is_saved=True
    )

    # Optionally add to collections
    if data and data.collection_ids:
        collection_service = CollectionService(db)
        await collection_service.add_to_collections(
            user_uuid, content_id, data.collection_ids
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

    await service.set_save_status(
        user_id=user_uuid, content_id=content_id, is_saved=False
    )

    await db.commit()
    return {"status": "ok", "is_saved": False}


@router.post("/{content_id}/like", status_code=status.HTTP_200_OK)
async def like_content(
    content_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Ajoute un like sur un contenu."""
    service = ContentService(db)
    user_uuid = UUID(current_user_id)

    await service.set_like_status(
        user_id=user_uuid,
        content_id=content_id,
        is_liked=True,
    )

    await db.commit()
    return {"status": "ok", "is_liked": True}


@router.delete("/{content_id}/like", status_code=status.HTTP_200_OK)
async def unlike_content(
    content_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Retire le like d'un contenu."""
    service = ContentService(db)
    user_uuid = UUID(current_user_id)

    await service.set_like_status(
        user_id=user_uuid,
        content_id=content_id,
        is_liked=False,
    )

    await db.commit()
    return {"status": "ok", "is_liked": False}


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

    await service.set_hide_status(
        user_id=user_uuid, content_id=content_id, is_hidden=True, reason=request.reason
    )

    await db.commit()
    return {"status": "ok", "is_hidden": True, "reason": request.reason}


@router.put(
    "/{content_id}/note", status_code=status.HTTP_200_OK, response_model=NoteResponse
)
async def upsert_note(
    content_id: UUID,
    request: NoteUpsertRequest,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Crée ou met à jour une note sur un article. Auto-sauvegarde l'article."""
    service = ContentService(db)
    user_uuid = UUID(current_user_id)

    try:
        result = await service.upsert_note(
            user_id=user_uuid,
            content_id=content_id,
            note_text=request.note_text,
        )
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))

    await db.commit()
    return NoteResponse(
        note_text=result.note_text,
        note_updated_at=result.note_updated_at,
        is_saved=result.is_saved,
    )


@router.delete("/{content_id}/note", status_code=status.HTTP_200_OK)
async def delete_note(
    content_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Supprime la note d'un article. L'article reste sauvegardé."""
    service = ContentService(db)
    user_uuid = UUID(current_user_id)

    result = await service.delete_note(user_id=user_uuid, content_id=content_id)
    if not result:
        raise HTTPException(status_code=404, detail="Status not found")

    await db.commit()
    return {"status": "ok"}


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
    import structlog
    from sqlalchemy import select

    from app.models.content import Content
    from app.services.perspective_service import PerspectiveService

    logger = structlog.get_logger(__name__)

    logger.info(
        "perspectives_endpoint_start",
        content_id=str(content_id),
        user_id=current_user_id,
    )

    # Get the content title
    result = await db.execute(select(Content).where(Content.id == content_id))
    content = result.scalars().first()

    if not content:
        logger.warning(
            "perspectives_content_not_found",
            content_id=str(content_id),
        )
        raise HTTPException(status_code=404, detail="Content not found")

    logger.info(
        "perspectives_content_found",
        content_id=str(content_id),
        title=content.title[:50] if content.title else "N/A",
    )

    # Search perspectives with exclusions
    service = PerspectiveService()
    keywords = service.extract_keywords(content.title)

    if not keywords:
        logger.warning(
            "perspectives_no_keywords",
            content_id=str(content_id),
            title=content.title,
        )
        return {"content_id": str(content_id), "perspectives": [], "keywords": []}

    perspectives = await service.search_perspectives(
        keywords, exclude_url=content.url, exclude_title=content.title
    )

    # Calculate bias distribution
    bias_distribution = {
        "left": 0,
        "center-left": 0,
        "center": 0,
        "center-right": 0,
        "right": 0,
        "unknown": 0,
    }
    for p in perspectives:
        bias_distribution[p.bias_stance] = bias_distribution.get(p.bias_stance, 0) + 1

    logger.info(
        "perspectives_endpoint_success",
        content_id=str(content_id),
        perspectives_count=len(perspectives),
        keywords=keywords,
    )

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
        "bias_distribution": bias_distribution,
    }
