"""Router pour les endpoints de personnalisation du feed (Story 4.7)."""

from typing import Optional, List
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.database import get_db
from app.dependencies import get_current_user_id
from app.models.user_personalization import UserPersonalization

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
    
    # Upsert: Insert if not exists, update if exists
    stmt = pg_insert(UserPersonalization).values(
        user_id=user_uuid,
        muted_sources=[request.source_id]
    ).on_conflict_do_update(
        index_elements=['user_id'],
        set_={
            'muted_sources': UserPersonalization.muted_sources.op('||')([request.source_id]),
            'updated_at': 'now()'
        }
    )
    
    await db.execute(stmt)
    await db.commit()
    
    return {"message": "Source mutée avec succès", "source_id": str(request.source_id)}


@router.post("/mute-theme")
async def mute_theme(
    request: MuteThemeRequest,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Ajoute un thème à la liste des thèmes mutés."""
    user_uuid = UUID(current_user_id)
    theme_slug = request.theme.lower().strip()
    
    stmt = pg_insert(UserPersonalization).values(
        user_id=user_uuid,
        muted_themes=[theme_slug]
    ).on_conflict_do_update(
        index_elements=['user_id'],
        set_={
            'muted_themes': UserPersonalization.muted_themes.op('||')([theme_slug]),
            'updated_at': 'now()'
        }
    )
    
    await db.execute(stmt)
    await db.commit()
    
    return {"message": f"Thème '{theme_slug}' muté avec succès"}


@router.post("/mute-topic")
async def mute_topic(
    request: MuteTopicRequest,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Ajoute un topic à la liste des topics mutés."""
    user_uuid = UUID(current_user_id)
    topic_slug = request.topic.lower().strip()
    
    stmt = pg_insert(UserPersonalization).values(
        user_id=user_uuid,
        muted_topics=[topic_slug]
    ).on_conflict_do_update(
        index_elements=['user_id'],
        set_={
            'muted_topics': UserPersonalization.muted_topics.op('||')([topic_slug]),
            'updated_at': 'now()'
        }
    )
    
    await db.execute(stmt)
    await db.commit()
    
    return {"message": f"Topic '{topic_slug}' muté avec succès"}


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
