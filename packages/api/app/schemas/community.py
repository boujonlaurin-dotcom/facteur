"""Schemas for community recommendation carousels (🌻)."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel

from app.schemas.content import SourceMini


class CommunityCarouselItem(BaseModel):
    """Single article in a community recommendation carousel."""

    content_id: UUID
    title: str
    url: str
    thumbnail_url: str | None = None
    description: str | None = None
    content_type: str = "article"
    duration_seconds: int | None = None
    published_at: datetime
    source: SourceMini
    sunflower_count: int = 0
    is_liked: bool = False
    is_saved: bool = False
    topics: list[str] = []

    class Config:
        from_attributes = True


class CommunityCarouselsResponse(BaseModel):
    """Response for GET /api/community/recommendations."""

    feed_carousel: list[CommunityCarouselItem] = []
    digest_carousel: list[CommunityCarouselItem] = []
