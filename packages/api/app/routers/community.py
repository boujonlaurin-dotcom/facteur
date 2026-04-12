"""Router for community recommendations (🌻 sunflower carousels)."""

import datetime
from uuid import UUID

import structlog
from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user_id
from app.models.content import UserContentStatus
from app.schemas.community import (
    CommunityCarouselItem,
    CommunityCarouselsResponse,
)
from app.services.community_recommendation_service import (
    CommunityRecommendationService,
)

logger = structlog.get_logger()

router = APIRouter()


def _content_to_carousel_item(
    item: dict,
    user_statuses: dict | None = None,
) -> CommunityCarouselItem | None:
    """Convert a community recommendation dict to a carousel item.

    Returns None if the content is missing required fields (e.g. no source),
    so the caller can filter it out instead of failing the whole response.
    """
    content = item["content"]
    status = (user_statuses or {}).get(content.id, {})

    if content.source is None:
        return None

    content_type = content.content_type
    content_type_str = (
        content_type.value if hasattr(content_type, "value") else str(content_type)
    )
    source_type = content.source.source_type
    source_type_str = (
        source_type.value if hasattr(source_type, "value") else str(source_type)
    )

    try:
        return CommunityCarouselItem(
            content_id=content.id,
            title=content.title or "",
            url=content.url or "",
            thumbnail_url=content.thumbnail_url,
            description=content.description,
            content_type=content_type_str,
            duration_seconds=content.duration_seconds,
            # Fallback to now() if null — pydantic schema requires a value
            published_at=content.published_at or datetime.datetime.now(datetime.UTC),
            source={
                "id": content.source.id,
                "name": content.source.name,
                "logo_url": content.source.logo_url,
                "type": source_type_str,
                "theme": content.source.theme,
            },
            sunflower_count=item.get("sunflower_count", 0),
            is_liked=status.get("is_liked", False),
            is_saved=status.get("is_saved", False),
            topics=content.topics or [],
        )
    except Exception:
        logger.exception(
            "community_carousel_item_build_failed", content_id=str(content.id)
        )
        return None


@router.get(
    "/recommendations",
    response_model=CommunityCarouselsResponse,
)
async def get_community_recommendations(
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Get community recommendation carousels for Feed and Digest.

    - Feed carousel: top articles by decay-weighted score over 7 days
    - Digest carousel: most recently sunflowered articles (non-overlapping)

    Fails open: if scoring/enrichment crashes for any reason, returns empty
    carousels so mobile never sees a 500 on this optional surface.
    """
    try:
        service = CommunityRecommendationService(db)
        user_uuid = UUID(current_user_id)

        feed_items, digest_items = await service.get_community_carousels()

        all_content_ids = [item["content"].id for item in feed_items + digest_items]
        user_statuses: dict = {}
        if all_content_ids:
            rows = (
                await db.execute(
                    select(UserContentStatus).where(
                        UserContentStatus.user_id == user_uuid,
                        UserContentStatus.content_id.in_(all_content_ids),
                    )
                )
            ).scalars().all()
            for row in rows:
                user_statuses[row.content_id] = {
                    "is_liked": row.is_liked,
                    "is_saved": row.is_saved,
                }

        feed_carousel = [
            ci
            for ci in (
                _content_to_carousel_item(item, user_statuses) for item in feed_items
            )
            if ci is not None
        ]
        digest_carousel = [
            ci
            for ci in (
                _content_to_carousel_item(item, user_statuses)
                for item in digest_items
            )
            if ci is not None
        ]

        return CommunityCarouselsResponse(
            feed_carousel=feed_carousel,
            digest_carousel=digest_carousel,
        )
    except Exception:
        logger.exception("community_recommendations_failed")
        return CommunityCarouselsResponse()
