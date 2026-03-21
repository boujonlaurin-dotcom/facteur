"""Router pour les endpoints Custom Topics (Epic 11).

CRUD pour les topics personnalisés + endpoint suggestions + popular entities.
"""

import json
from datetime import UTC, datetime, timedelta
from uuid import UUID

import structlog
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, field_validator
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user_id
from app.models.content import Content, UserContentStatus
from app.models.enums import ContentStatus
from app.models.user import UserSubtopic
from app.models.user_topic_profile import UserTopicProfile
from app.services.ml.classification_service import (
    SLUG_TO_LABEL,
    VALID_ENTITY_TYPES,
    VALID_TOPIC_SLUGS,
)
from app.services.ml.topic_enrichment_service import get_topic_enrichment_service
from app.services.user_service import UserService

logger = structlog.get_logger()

router = APIRouter()


# --- Pydantic Schemas ---


class CreateTopicRequest(BaseModel):
    name: str
    entity_type: str | None = None
    priority_multiplier: float | None = None

    @field_validator("priority_multiplier")
    @classmethod
    def validate_create_multiplier(cls, v: float | None) -> float | None:
        if v is not None:
            allowed = {0.5, 1.0, 2.0}
            if v not in allowed:
                raise ValueError(
                    f"priority_multiplier doit être 0.5, 1.0 ou 2.0 (reçu: {v})"
                )
        return v

    @field_validator("name")
    @classmethod
    def name_must_not_be_empty(cls, v: str) -> str:
        v = v.strip()
        if not v or len(v) < 2:
            raise ValueError("Le nom du topic doit contenir au moins 2 caractères")
        if len(v) > 200:
            raise ValueError("Le nom du topic ne peut pas dépasser 200 caractères")
        return v

    @field_validator("entity_type")
    @classmethod
    def validate_entity_type(cls, v: str | None) -> str | None:
        if v is not None and v.upper() not in VALID_ENTITY_TYPES:
            raise ValueError(
                f"entity_type doit être PERSON, ORG, EVENT, LOCATION ou PRODUCT (reçu: {v})"
            )
        return v.upper() if v else None


class UpdateTopicRequest(BaseModel):
    priority_multiplier: float

    @field_validator("priority_multiplier")
    @classmethod
    def validate_multiplier(cls, v: float) -> float:
        allowed = {0.5, 1.0, 2.0}
        if v not in allowed:
            raise ValueError(
                f"priority_multiplier doit être 0.5, 1.0 ou 2.0 (reçu: {v})"
            )
        return v


class TopicResponse(BaseModel):
    id: UUID
    topic_name: str
    slug_parent: str
    keywords: list[str]
    intent_description: str | None
    priority_multiplier: float
    composite_score: float
    source_type: str
    entity_type: str | None = None
    canonical_name: str | None = None
    created_at: str

    model_config = {"from_attributes": True}


class TopicSuggestion(BaseModel):
    slug: str
    label: str
    article_count: int


class PopularEntityResponse(BaseModel):
    name: str
    type: str
    theme: str | None
    count: int


def _topic_to_response(t: UserTopicProfile) -> TopicResponse:
    """Convert a UserTopicProfile ORM object to TopicResponse."""
    return TopicResponse(
        id=t.id,
        topic_name=t.topic_name,
        slug_parent=t.slug_parent,
        keywords=t.keywords or [],
        intent_description=t.intent_description,
        priority_multiplier=t.priority_multiplier,
        composite_score=t.composite_score,
        source_type=t.source_type,
        entity_type=t.entity_type,
        canonical_name=t.canonical_name,
        created_at=t.created_at.isoformat() if t.created_at else "",
    )


# --- Endpoints ---


@router.get("/popular-entities", response_model=list[PopularEntityResponse])
async def get_popular_entities(
    theme: str | None = Query(None, description="Theme slug to filter by"),
    limit: int = Query(10, ge=1, le=50),
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Retourne les entités les plus fréquentes dans les articles des 30 derniers jours."""
    cutoff = datetime.now(UTC) - timedelta(days=30)

    # Unnest entities JSON strings, group and count
    unnested = func.unnest(Content.entities).label("entity_json")
    stmt = select(unnested, Content.theme, func.count().label("cnt")).where(
        Content.published_at >= cutoff,
        Content.entities.isnot(None),
    )
    if theme:
        stmt = stmt.where(Content.theme == theme)

    stmt = (
        stmt.group_by("entity_json", Content.theme)
        .order_by(func.count().desc())
        .limit(limit * 3)
    )

    rows = (await db.execute(stmt)).all()

    # Deduplicate by entity name (case-insensitive) and parse JSON
    seen: dict[str, PopularEntityResponse] = {}
    for row in rows:
        try:
            entity = json.loads(row.entity_json)
        except (json.JSONDecodeError, TypeError):
            continue
        name = entity.get("name", "")
        etype = entity.get("type", "")
        if not name or not etype:
            continue
        key = name.lower()
        if key in seen:
            seen[key].count += row.cnt
        else:
            seen[key] = PopularEntityResponse(
                name=name,
                type=etype,
                theme=row.theme if theme else None,
                count=row.cnt,
            )

    # Sort by count and return top N
    results = sorted(seen.values(), key=lambda x: x.count, reverse=True)[:limit]
    return results


@router.get("/", response_model=list[TopicResponse])
async def list_topics(
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Liste les custom topics de l'utilisateur."""
    user_uuid = UUID(current_user_id)

    stmt = (
        select(UserTopicProfile)
        .where(UserTopicProfile.user_id == user_uuid)
        .order_by(UserTopicProfile.created_at.desc())
    )
    results = (await db.scalars(stmt)).all()

    return [_topic_to_response(t) for t in results]


@router.post("/", response_model=TopicResponse, status_code=201)
async def create_topic(
    request: CreateTopicRequest,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Crée un custom topic via enrichissement LLM.

    Si entity_type est fourni, crée un abonnement entité (canonical_name = name).
    """
    user_uuid = UUID(current_user_id)

    # Ensure user profile exists (FK constraint)
    user_service = UserService(db)
    await user_service.get_or_create_profile(current_user_id)
    await db.flush()

    # LLM enrichment (always, for slug_parent + keywords)
    enrichment_service = get_topic_enrichment_service()
    try:
        result = await enrichment_service.enrich(request.name)
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))

    # Determine entity fields (explicit request OR auto-detected by enrichment)
    entity_type = request.entity_type or result.entity_type
    canonical_name = request.name.strip() if entity_type else None

    # Duplicate check depends on entity vs topic subscription
    if canonical_name:
        existing = await db.scalar(
            select(UserTopicProfile).where(
                UserTopicProfile.user_id == user_uuid,
                UserTopicProfile.canonical_name == canonical_name,
            )
        )
        if existing:
            raise HTTPException(
                status_code=409,
                detail=f"Tu suis déjà l'entité '{canonical_name}'",
            )
    else:
        existing = await db.scalar(
            select(UserTopicProfile).where(
                UserTopicProfile.user_id == user_uuid,
                UserTopicProfile.slug_parent == result.slug_parent,
                UserTopicProfile.canonical_name.is_(None),
            )
        )
        if existing:
            raise HTTPException(
                status_code=409,
                detail=(
                    f"Tu suis déjà un topic dans la catégorie "
                    f"'{SLUG_TO_LABEL.get(result.slug_parent, result.slug_parent)}'"
                ),
            )

    topic = UserTopicProfile(
        user_id=user_uuid,
        topic_name=request.name.strip(),
        slug_parent=result.slug_parent,
        keywords=result.keywords,
        intent_description=result.intent_description,
        entity_type=entity_type,
        canonical_name=canonical_name,
        source_type="explicit",
        priority_multiplier=request.priority_multiplier if request.priority_multiplier is not None else 1.0,
        composite_score=0.0,
    )
    db.add(topic)
    await db.flush()
    await db.refresh(topic)

    logger.info(
        "custom_topic_created",
        user_id=current_user_id,
        topic_name=request.name,
        slug=result.slug_parent,
        entity_type=entity_type,
    )

    return _topic_to_response(topic)


@router.put("/{topic_id}", response_model=TopicResponse)
async def update_topic(
    topic_id: UUID,
    request: UpdateTopicRequest,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Met à jour le priority_multiplier d'un custom topic."""
    user_uuid = UUID(current_user_id)

    topic = await db.scalar(
        select(UserTopicProfile).where(
            UserTopicProfile.id == topic_id,
            UserTopicProfile.user_id == user_uuid,
        )
    )
    if not topic:
        raise HTTPException(status_code=404, detail="Topic non trouvé")

    topic.priority_multiplier = request.priority_multiplier
    await db.flush()
    await db.refresh(topic)

    logger.info(
        "custom_topic_updated",
        user_id=current_user_id,
        topic_id=str(topic_id),
        multiplier=request.priority_multiplier,
    )

    return _topic_to_response(topic)


@router.delete("/{topic_id}", status_code=200)
async def delete_topic(
    topic_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Supprime un custom topic."""
    user_uuid = UUID(current_user_id)

    topic = await db.scalar(
        select(UserTopicProfile).where(
            UserTopicProfile.id == topic_id,
            UserTopicProfile.user_id == user_uuid,
        )
    )
    if not topic:
        raise HTTPException(status_code=404, detail="Topic non trouvé")

    # Also remove matching UserSubtopic so the algorithm
    # no longer weights this topic in recommendations
    slug = topic.slug_parent
    await db.delete(topic)
    if slug:
        await db.execute(
            delete(UserSubtopic).where(
                UserSubtopic.user_id == user_uuid,
                UserSubtopic.topic_slug == slug,
            )
        )

    logger.info(
        "custom_topic_deleted",
        user_id=current_user_id,
        topic_id=str(topic_id),
        slug_parent=slug,
    )

    return {"message": "Topic supprimé avec succès"}


@router.get("/suggestions", response_model=list[TopicSuggestion])
async def get_suggestions(
    theme: str | None = Query(
        None, description="Theme slug to get suggestions for (e.g. 'tech')"
    ),
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Retourne des suggestions de topics basées sur les lectures récentes.

    Suggère les slugs les plus lus par l'utilisateur qui ne sont pas
    encore dans ses UserTopicProfile.
    """
    user_uuid = UUID(current_user_id)

    # Deferred import to avoid circular dependency at module level
    from app.services.ml.topic_theme_mapper import TOPIC_TO_THEME

    # Get user's existing custom topic slugs
    existing_slugs_stmt = select(UserTopicProfile.slug_parent).where(
        UserTopicProfile.user_id == user_uuid
    )
    existing_slugs = set((await db.scalars(existing_slugs_stmt)).all())

    # Find top consumed topics from user's reading history
    # Unnest content.topics array, count occurrences, filter out already-followed
    stmt = (
        select(
            func.unnest(Content.topics).label("topic_slug"),
            func.count().label("article_count"),
        )
        .join(
            UserContentStatus,
            (UserContentStatus.content_id == Content.id)
            & (UserContentStatus.user_id == user_uuid),
        )
        .where(
            UserContentStatus.status == ContentStatus.CONSUMED,
            Content.topics.isnot(None),
        )
        .group_by("topic_slug")
        .order_by(func.count().desc())
        .limit(20)
    )

    rows = (await db.execute(stmt)).all()

    suggestions = []
    for row in rows:
        slug = row.topic_slug
        count = row.article_count

        # Filter: must be a valid slug, not already followed
        if slug not in VALID_TOPIC_SLUGS:
            continue
        if slug in existing_slugs:
            continue

        # If theme filter provided, check topic belongs to that theme
        if theme and TOPIC_TO_THEME.get(slug) != theme:
            continue

        label = SLUG_TO_LABEL.get(slug, slug.capitalize())
        suggestions.append(TopicSuggestion(slug=slug, label=label, article_count=count))

        if len(suggestions) >= 4:
            break

    return suggestions
