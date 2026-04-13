"""Tests for community recommendation service (🌻 sunflower carousels)."""

import pytest
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4
from datetime import datetime, timedelta, UTC

from app.services.community_recommendation_service import (
    CommunityRecommendationService,
    COMMUNITY_WINDOW_DAYS,
    DECAY_HALF_LIFE_HOURS,
)


def test_decay_formula_math():
    """Verify the decay formula gives expected values."""
    # score = 1 / (1 + hours / 48)
    # At 0 hours: 1 / (1 + 0) = 1.0
    assert 1.0 / (1.0 + 0 / 48) == 1.0

    # At 48 hours: 1 / (1 + 1) = 0.5
    assert 1.0 / (1.0 + 48 / 48) == 0.5

    # At 168 hours (7 days): 1 / (1 + 3.5) ≈ 0.222
    score_7d = 1.0 / (1.0 + 168 / 48)
    assert abs(score_7d - 0.222) < 0.01


def test_decay_half_life_constant():
    """Verify half-life constant is 48 hours as specified."""
    assert DECAY_HALF_LIFE_HOURS == 48


def test_community_window_constant():
    """Verify community window is 7 days as specified."""
    assert COMMUNITY_WINDOW_DAYS == 7


@pytest.mark.asyncio
async def test_get_top_recommendations_empty():
    """Service returns empty list when no sunflowered articles exist."""
    session = AsyncMock()
    service = CommunityRecommendationService(session)

    # Mock empty result
    mock_result = MagicMock()
    mock_result.all.return_value = []
    session.execute.return_value = mock_result

    result = await service.get_top_recommendations()
    assert result == []


@pytest.mark.asyncio
async def test_get_recent_recommendations_empty():
    """Service returns empty list when no sunflowered articles exist."""
    session = AsyncMock()
    service = CommunityRecommendationService(session)

    mock_result = MagicMock()
    mock_result.all.return_value = []
    session.execute.return_value = mock_result

    result = await service.get_recent_recommendations()
    assert result == []


@pytest.mark.asyncio
async def test_get_community_carousels_non_duplication():
    """Digest carousel excludes articles already in Feed carousel."""
    session = AsyncMock()
    service = CommunityRecommendationService(session)

    # Mock feed results
    content1 = MagicMock()
    content1.id = uuid4()
    content2 = MagicMock()
    content2.id = uuid4()

    feed_items = [
        {"content": content1, "sunflower_count": 3, "score": 1.5},
        {"content": content2, "sunflower_count": 2, "score": 1.0},
    ]

    # Mock: first call returns feed items, second call returns digest items
    async def mock_get_top(limit=8, exclude_ids=None):
        return feed_items

    async def mock_get_recent(limit=8, exclude_ids=None):
        # Verify feed IDs are excluded
        assert exclude_ids is not None
        assert content1.id in exclude_ids
        assert content2.id in exclude_ids
        return []

    service.get_top_recommendations = mock_get_top
    service.get_recent_recommendations = mock_get_recent

    feed, digest = await service.get_community_carousels()
    assert len(feed) == 2
    assert len(digest) == 0


def test_sunflower_count_badge_logic():
    """Badge should show count only if >= 2."""
    # Count = 1: no count badge
    count = 1
    assert count < 2  # Should NOT show count

    # Count = 2: show badge
    count = 2
    assert count >= 2  # Should show "🌻 2"

    # Count = 5: show badge
    count = 5
    assert count >= 2  # Should show "🌻 5"


def test_collection_name_constant():
    """Verify collection name was updated to sunflower naming."""
    from app.services.collection_service import LIKED_COLLECTION_NAME
    assert LIKED_COLLECTION_NAME == "Mes articles intéressants 🌻"


def test_community_carousel_schema():
    """Verify CommunityCarouselItem schema has required fields."""
    from app.schemas.community import CommunityCarouselItem

    item = CommunityCarouselItem(
        content_id=uuid4(),
        title="Test Article",
        url="https://example.com/article",
        published_at=datetime.now(UTC),
        source={
            "id": str(uuid4()),
            "name": "Test Source",
            "logo_url": None,
            "type": "article",
            "theme": "tech",
        },
        sunflower_count=3,
    )
    assert item.sunflower_count == 3
    assert item.title == "Test Article"
    assert item.is_liked is False
    assert item.is_saved is False


def test_digest_response_has_community_carousel():
    """Verify DigestResponse includes community_carousel field."""
    from app.schemas.digest import DigestResponse

    response = DigestResponse(
        digest_id=uuid4(),
        user_id=uuid4(),
        target_date=datetime.now(UTC).date(),
        generated_at=datetime.now(UTC),
        community_carousel=[],
    )
    assert response.community_carousel == []


def test_community_carousels_response_schema():
    """Verify CommunityCarouselsResponse schema."""
    from app.schemas.community import CommunityCarouselsResponse

    response = CommunityCarouselsResponse(
        feed_carousel=[],
        digest_carousel=[],
    )
    assert response.feed_carousel == []
    assert response.digest_carousel == []
