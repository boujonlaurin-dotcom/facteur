"""Router pour les endpoints de personnalisation du feed (Story 4.7)."""

from typing import Optional, List
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select, func, text
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.database import get_db
from app.dependencies import get_current_user_id
from app.models.user_personalization import UserPersonalization

from app.services.user_service import UserService

import structlog

logger = structlog.get_logger()

router = APIRouter()


# --- Pydantic Schemas ---

class MuteSourceRequest(BaseModel):
    source_id: UUID


class MuteThemeRequest(BaseModel):
    theme: str  # e.g., "politics"


class MuteTopicRequest(BaseModel):
    topic: str  # e.g., "crypto"


class PersonalizationResponse(BaseModel):
    muted_sources: List[UUID] = []
    muted_themes: List[str] = []
    muted_topics: List[str] = []


# --- Endpoints ---

@router.get("/", response_model=PersonalizationResponse)
async def get_personalization(
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Récupère les préférences de personnalisation de l'utilisateur."""
    user_uuid = UUID(current_user_id)
    
    result = await db.scalar(
        select(UserPersonalization).where(UserPersonalization.user_id == user_uuid)
    )
    
    if not result:
        return PersonalizationResponse()
    
    return PersonalizationResponse(
        muted_sources=result.muted_sources or [],
        muted_themes=result.muted_themes or [],
        muted_topics=result.muted_topics or []
    )


@router.post("/mute-source")
async def mute_source(
    request: MuteSourceRequest,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Ajoute une source à la liste des sources mutées."""
    user_uuid = UUID(current_user_id)
    # Garantir l'existence du profil utilisateur (requis pour la FK)
    
    # Garantir l'existence du profil utilisateur (requis pour la FK)
    user_service = UserService(db)
    # Ensure profile exists to satisfy FK constraint
    await user_service.get_or_create_profile(current_user_id)
    await db.commit()  # S'assurer que le profil est persisté et visible pour la FK
    

    try:
        # Upsert: Insert if not exists, update if exists
        # Use COALESCE to handle case where muted_sources is NULL
        stmt = pg_insert(UserPersonalization).values(
            user_id=user_uuid,
            muted_sources=[request.source_id]
        ).on_conflict_do_update(
            index_elements=['user_id'],
            set_={
                'muted_sources': func.coalesce(UserPersonalization.muted_sources, text("'{}'::uuid[]")).op('||')([request.source_id]),
                'updated_at': func.now()
            }
        )
        
        await db.execute(stmt)
        await db.commit()
        return {"message": "Source mutée avec succès", "source_id": str(request.source_id)}
        
    except Exception as e:
        logger.error("mute_source_error", error=str(e), user_id=str(user_uuid), source_id=str(request.source_id))
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Erreur lors du masquage de la source: {str(e)}")


@router.post("/mute-theme")
async def mute_theme(
    request: MuteThemeRequest,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Ajoute un thème à la liste des thèmes mutés."""
    user_uuid = UUID(current_user_id)
    # Garantir l'existence du profil utilisateur (requis pour la FK)
    theme_slug = request.theme.lower().strip()
    
    # Garantir l'existence du profil utilisateur (requis pour la FK)
    user_service = UserService(db)
    # Ensure profile exists to satisfy FK constraint
    await user_service.get_or_create_profile(current_user_id)
    await db.commit()
    

    try:
        stmt = pg_insert(UserPersonalization).values(
            user_id=user_uuid,
            muted_themes=[theme_slug]
        ).on_conflict_do_update(
            index_elements=['user_id'],
            set_={
                'muted_themes': func.coalesce(UserPersonalization.muted_themes, text("'{}'::text[]")).op('||')([theme_slug]),
                'updated_at': func.now()
            }
        )
        
        await db.execute(stmt)
        await db.commit()
        
        return {"message": f"Thème '{theme_slug}' muté avec succès"}

    except Exception as e:
        logger.error("mute_theme_error", error=str(e), user_id=str(user_uuid), theme=theme_slug)
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Erreur lors du masquage du thème: {str(e)}")


@router.post("/mute-topic")
async def mute_topic(
    request: MuteTopicRequest,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    # Garantir l'existence du profil utilisateur (requis pour la FK)
    user_uuid = UUID(current_user_id)
    topic_slug = request.topic.lower().strip()
    
    # Garantir l'existence du profil utilisateur (requis pour la FK)
    user_service = UserService(db)
    # Ensure profile exists to satisfy FK constraint
    await user_service.get_or_create_profile(current_user_id)
    await db.commit()
    

    try:
        stmt = pg_insert(UserPersonalization).values(
            user_id=user_uuid,
            muted_topics=[topic_slug]
        ).on_conflict_do_update(
            index_elements=['user_id'],
            set_={
                'muted_topics': func.coalesce(UserPersonalization.muted_topics, text("'{}'::text[]")).op('||')([topic_slug]),
                'updated_at': func.now()
            }
        )
        
        await db.execute(stmt)
        await db.commit()
        
        return {"message": f"Topic '{topic_slug}' muté avec succès"}

    except Exception as e:
        logger.error("mute_topic_error", error=str(e), user_id=str(user_uuid), topic=topic_slug)
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Erreur lors du masquage du topic: {str(e)}")


@router.delete("/unmute-source/{source_id}")
async def unmute_source(
    source_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Retire une source de la liste des sources mutées."""
    user_uuid = UUID(current_user_id)
    
    result = await db.scalar(
        select(UserPersonalization).where(UserPersonalization.user_id == user_uuid)
    )
    
    if not result:
        raise HTTPException(status_code=404, detail="Pas de préférences trouvées")
    
    if source_id in result.muted_sources:
        new_list = [s for s in result.muted_sources if s != source_id]
        result.muted_sources = new_list
        await db.commit()
    
    return {"message": "Source démuée avec succès", "source_id": str(source_id)}
