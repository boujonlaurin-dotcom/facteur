"""Router pour les endpoints de personnalisation du feed (Story 4.7 + Epic 13)."""

from uuid import UUID

import structlog
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import func, select, text
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user_id
from app.models.source import UserSource
from app.models.user_personalization import UserPersonalization
from app.schemas.learning import (
    EntityPreferenceRequest,
    EntityPreferenceResponse,
)
from app.services.feed_cache import FEED_CACHE
from app.services.learning_service import LearningService
from app.services.sources_cache import SOURCES_CACHE
from app.services.user_service import UserService

logger = structlog.get_logger()

router = APIRouter()


# --- Pydantic Schemas ---


class MuteSourceRequest(BaseModel):
    source_id: UUID


class MuteThemeRequest(BaseModel):
    theme: str  # e.g., "politics"


class MuteTopicRequest(BaseModel):
    topic: str  # e.g., "crypto"


class MuteContentTypeRequest(BaseModel):
    content_type: str  # e.g., "podcast", "youtube", "article"


class TogglePaidContentRequest(BaseModel):
    hide_paid: bool


class PersonalizationResponse(BaseModel):
    muted_sources: list[UUID] = []
    muted_themes: list[str] = []
    muted_topics: list[str] = []
    muted_content_types: list[str] = []
    hide_paid_content: bool = True


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
        muted_topics=result.muted_topics or [],
        muted_content_types=result.muted_content_types or [],
        hide_paid_content=result.hide_paid_content
        if result.hide_paid_content is not None
        else True,
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
        stmt = (
            pg_insert(UserPersonalization)
            .values(user_id=user_uuid, muted_sources=[request.source_id])
            .on_conflict_do_update(
                index_elements=["user_id"],
                set_={
                    "muted_sources": func.array_append(
                        func.array_remove(
                            func.coalesce(
                                UserPersonalization.muted_sources,
                                text("ARRAY[]::uuid[]"),
                            ),
                            request.source_id,
                        ),
                        request.source_id,
                    ),
                    "updated_at": func.now(),
                },
            )
        )

        await db.execute(stmt)

        # Auto-untrust: muting a source removes it from followed sources
        existing_trust = await db.scalar(
            select(UserSource).where(
                UserSource.user_id == user_uuid,
                UserSource.source_id == request.source_id,
            )
        )
        if existing_trust:
            await db.delete(existing_trust)

        await db.commit()
        FEED_CACHE.invalidate(user_uuid)
        SOURCES_CACHE.invalidate(user_uuid)
        return {
            "message": "Source mutée avec succès",
            "source_id": str(request.source_id),
        }

    except Exception as e:
        logger.error(
            "mute_source_error",
            error=str(e),
            user_id=str(user_uuid),
            source_id=str(request.source_id),
        )
        await db.rollback()
        raise HTTPException(
            status_code=500, detail=f"Erreur lors du masquage de la source: {str(e)}"
        )


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
        stmt = (
            pg_insert(UserPersonalization)
            .values(user_id=user_uuid, muted_themes=[theme_slug])
            .on_conflict_do_update(
                index_elements=["user_id"],
                set_={
                    "muted_themes": func.array_append(
                        func.array_remove(
                            func.coalesce(
                                UserPersonalization.muted_themes,
                                text("ARRAY[]::text[]"),
                            ),
                            theme_slug,
                        ),
                        theme_slug,
                    ),
                    "updated_at": func.now(),
                },
            )
        )

        await db.execute(stmt)
        await db.commit()
        FEED_CACHE.invalidate(user_uuid)

        return {"message": f"Thème '{theme_slug}' muté avec succès"}

    except Exception as e:
        logger.error(
            "mute_theme_error", error=str(e), user_id=str(user_uuid), theme=theme_slug
        )
        await db.rollback()
        raise HTTPException(
            status_code=500, detail=f"Erreur lors du masquage du thème: {str(e)}"
        )


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
        stmt = (
            pg_insert(UserPersonalization)
            .values(user_id=user_uuid, muted_topics=[topic_slug])
            .on_conflict_do_update(
                index_elements=["user_id"],
                set_={
                    "muted_topics": func.array_append(
                        func.array_remove(
                            func.coalesce(
                                UserPersonalization.muted_topics,
                                text("ARRAY[]::text[]"),
                            ),
                            topic_slug,
                        ),
                        topic_slug,
                    ),
                    "updated_at": func.now(),
                },
            )
        )

        await db.execute(stmt)
        await db.commit()
        FEED_CACHE.invalidate(user_uuid)

        return {"message": f"Topic '{topic_slug}' muté avec succès"}

    except Exception as e:
        logger.error(
            "mute_topic_error", error=str(e), user_id=str(user_uuid), topic=topic_slug
        )
        await db.rollback()
        raise HTTPException(
            status_code=500, detail=f"Erreur lors du masquage du topic: {str(e)}"
        )


@router.post("/mute-content-type")
async def mute_content_type(
    request: MuteContentTypeRequest,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Ajoute un type de contenu à la liste des types mutés."""
    user_uuid = UUID(current_user_id)
    ct_slug = request.content_type.lower().strip()

    # Valider que le type de contenu est valide
    valid_types = {"article", "podcast", "youtube"}
    if ct_slug not in valid_types:
        raise HTTPException(
            status_code=400,
            detail=f"Type de contenu invalide: '{ct_slug}'. Valeurs acceptées: {', '.join(valid_types)}",
        )

    user_service = UserService(db)
    await user_service.get_or_create_profile(current_user_id)
    await db.commit()

    try:
        stmt = (
            pg_insert(UserPersonalization)
            .values(user_id=user_uuid, muted_content_types=[ct_slug])
            .on_conflict_do_update(
                index_elements=["user_id"],
                set_={
                    "muted_content_types": func.array_append(
                        func.array_remove(
                            func.coalesce(
                                UserPersonalization.muted_content_types,
                                text("ARRAY[]::text[]"),
                            ),
                            ct_slug,
                        ),
                        ct_slug,
                    ),
                    "updated_at": func.now(),
                },
            )
        )

        await db.execute(stmt)
        await db.commit()
        FEED_CACHE.invalidate(user_uuid)

        return {"message": f"Type de contenu '{ct_slug}' muté avec succès"}

    except Exception as e:
        logger.error(
            "mute_content_type_error",
            error=str(e),
            user_id=str(user_uuid),
            content_type=ct_slug,
        )
        await db.rollback()
        raise HTTPException(
            status_code=500,
            detail=f"Erreur lors du masquage du type de contenu: {str(e)}",
        )


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
        FEED_CACHE.invalidate(user_uuid)
        SOURCES_CACHE.invalidate(user_uuid)

    return {"message": "Source démuée avec succès", "source_id": str(source_id)}


@router.delete("/unmute-theme/{theme}")
async def unmute_theme(
    theme: str,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Retire un thème de la liste des thèmes mutés."""
    user_uuid = UUID(current_user_id)
    theme_slug = theme.lower().strip()

    result = await db.scalar(
        select(UserPersonalization).where(UserPersonalization.user_id == user_uuid)
    )

    if not result:
        raise HTTPException(status_code=404, detail="Pas de préférences trouvées")

    if result.muted_themes and theme_slug in result.muted_themes:
        result.muted_themes = [t for t in result.muted_themes if t != theme_slug]
        await db.commit()
        FEED_CACHE.invalidate(user_uuid)

    return {"message": f"Thème '{theme_slug}' démuté"}


@router.delete("/unmute-topic/{topic}")
async def unmute_topic(
    topic: str,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Retire un topic de la liste des topics mutés."""
    user_uuid = UUID(current_user_id)
    topic_slug = topic.lower().strip()

    result = await db.scalar(
        select(UserPersonalization).where(UserPersonalization.user_id == user_uuid)
    )

    if not result:
        raise HTTPException(status_code=404, detail="Pas de préférences trouvées")

    if result.muted_topics and topic_slug in result.muted_topics:
        result.muted_topics = [t for t in result.muted_topics if t != topic_slug]
        await db.commit()
        FEED_CACHE.invalidate(user_uuid)

    return {"message": f"Topic '{topic_slug}' démuté"}


@router.delete("/unmute-content-type/{content_type}")
async def unmute_content_type(
    content_type: str,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Retire un type de contenu de la liste des types mutés."""
    user_uuid = UUID(current_user_id)
    ct_slug = content_type.lower().strip()

    result = await db.scalar(
        select(UserPersonalization).where(UserPersonalization.user_id == user_uuid)
    )

    if not result:
        raise HTTPException(status_code=404, detail="Pas de préférences trouvées")

    if result.muted_content_types and ct_slug in result.muted_content_types:
        result.muted_content_types = [
            t for t in result.muted_content_types if t != ct_slug
        ]
        await db.commit()
        FEED_CACHE.invalidate(user_uuid)

    return {"message": f"Type de contenu '{ct_slug}' démuté"}


@router.post("/toggle-paid-content")
async def toggle_paid_content(
    request: TogglePaidContentRequest,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Active/désactive le masquage des articles payants."""
    user_uuid = UUID(current_user_id)

    user_service = UserService(db)
    await user_service.get_or_create_profile(current_user_id)
    await db.commit()

    try:
        stmt = (
            pg_insert(UserPersonalization)
            .values(user_id=user_uuid, hide_paid_content=request.hide_paid)
            .on_conflict_do_update(
                index_elements=["user_id"],
                set_={"hide_paid_content": request.hide_paid, "updated_at": func.now()},
            )
        )

        await db.execute(stmt)
        await db.commit()
        FEED_CACHE.invalidate(user_uuid)

        return {
            "message": f"Filtrage articles payants {'activé' if request.hide_paid else 'désactivé'}",
            "hide_paid_content": request.hide_paid,
        }

    except Exception as e:
        logger.error("toggle_paid_content_error", error=str(e), user_id=str(user_uuid))
        await db.rollback()
        raise HTTPException(
            status_code=500, detail=f"Erreur lors du changement de préférence: {str(e)}"
        )


# --- Entity Preferences (follow / mute on named entities) ---


@router.post("/entity-preference", status_code=201)
async def set_entity_preference(
    request: EntityPreferenceRequest,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Cree ou met a jour une preference entite (follow/mute)."""
    user_uuid = UUID(current_user_id)

    if request.preference not in ("follow", "mute"):
        raise HTTPException(
            status_code=400,
            detail="Preference invalide. Valeurs: 'follow', 'mute'",
        )

    service = LearningService(db)
    await service.set_entity_preference(
        user_uuid, request.entity_canonical, request.preference
    )
    await db.commit()
    FEED_CACHE.invalidate(user_uuid)

    return EntityPreferenceResponse(
        entity_canonical=request.entity_canonical,
        preference=request.preference,
    )


@router.delete("/entity-preference/{entity_canonical}")
async def remove_entity_preference(
    entity_canonical: str,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Supprime une preference entite."""
    user_uuid = UUID(current_user_id)
    service = LearningService(db)
    removed = await service.remove_entity_preference(user_uuid, entity_canonical)
    await db.commit()
    FEED_CACHE.invalidate(user_uuid)

    if not removed:
        raise HTTPException(status_code=404, detail="Preference non trouvee")

    return {"message": f"Preference pour '{entity_canonical}' supprimee"}
