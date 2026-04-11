"""Router for community recommendations (🌻 sunflower carousels)."""

from uuid import UUID

import structlog
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user_id
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
) -> CommunityCarouselItem:
    """Convert a community recommendation dict to a carousel item."""
    content = item["content"]
    user_id_statuses = user_statuses or {}
    status = user_id_statuses.get(content.id, {})

    return CommunityCarouselItem(
        content_id=content.id,
        title=content.title,
        url=content.url,
        thumbnail_url=content.thumbnail_url,
        description=content.description,
        content_type=content.content_type.value if hasattr(content.content_type, "value") else str(content.content_type),
        duration_seconds=content.duration_seconds,
        published_at=content.published_at,
        source={
            "id": content.source.id,
            "name": content.source.name,
            "logo_url": content.source.logo_url,
            "type": content.source.source_type.value if hasattr(content.source.source_type, "value") else str(content.source.source_type),
            "theme": content.source.theme,
        },
        sunflower_count=item.get("sunflower_count", 0),
        is_liked=status.get("is_liked", False),
        is_saved=status.get("is_saved", False),
        topics=content.topics or [],
    )


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
    """
    from sqlalchemy import select

    from app.models.content import UserContentStatus

    service = CommunityRecommendationService(db)
    user_uuid = UUID(current_user_id)

    feed_items, digest_items = await service.get_community_carousels()

    # Fetch user's statuses for these articles
    all_content_ids = [
        item["content"].id for item in feed_items + digest_items
    ]
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
        _content_to_carousel_item(item, user_statuses)
        for item in feed_items
    ]
    digest_carousel = [
        _content_to_carousel_item(item, user_statuses)
        for item in digest_items
    ]

    return CommunityCarouselsResponse(
        feed_carousel=feed_carousel,
        digest_carousel=digest_carousel,
    )
