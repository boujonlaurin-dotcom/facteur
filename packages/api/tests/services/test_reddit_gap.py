"""Tests for the Reddit direct-resolution gap fix (Story 12.2, T0.3)."""

from unittest.mock import AsyncMock, MagicMock

import pytest

from app.services.rss_parser import DetectedFeed
from app.services.search.smart_source_search import SmartSourceSearchService


def _service():
    service = SmartSourceSearchService(db=MagicMock())
    service.reddit.search = AsyncMock(return_value=[])
    return service


@pytest.mark.asyncio
async def test_resolve_reddit_sub_direct_hit():
    service = _service()
    service.rss_parser.detect = AsyncMock(
        return_value=DetectedFeed(
            feed_url="https://www.reddit.com/r/ai/.rss",
            title="r/ai",
            feed_type="reddit",
            entries=[{"title": "hot post", "published_at": ""}],
        )
    )

    results = await service._search_reddit("r/ai", user_themes=[])
    assert len(results) == 1
    assert results[0]["feed_url"] == "https://www.reddit.com/r/ai/.rss"
    assert results[0]["type"] == "reddit"
    await service.close()


@pytest.mark.asyncio
async def test_bare_token_treated_as_subreddit():
    service = _service()
    service.rss_parser.detect = AsyncMock(
        return_value=DetectedFeed(
            feed_url="https://www.reddit.com/r/worldnews/.rss", title="r/worldnews"
        )
    )
    results = await service._search_reddit("worldnews", user_themes=[])
    assert results[0]["feed_url"] == "https://www.reddit.com/r/worldnews/.rss"
    await service.close()


@pytest.mark.asyncio
async def test_reddit_direct_failure_falls_back_to_search():
    service = _service()
    service.rss_parser.detect = AsyncMock(side_effect=ValueError("no such sub"))
    # Search API returns one discovery result.
    service.reddit.search = AsyncMock(
        return_value=[
            {
                "name": "r/science",
                "url": "https://www.reddit.com/r/science/",
                "feed_url": "https://www.reddit.com/r/science/.rss",
                "description": "science",
                "subscribers": 1000,
            }
        ]
    )
    results = await service._search_reddit("r/deadsub", user_themes=[])
    assert len(results) == 1
    assert results[0]["feed_url"] == "https://www.reddit.com/r/science/.rss"
    await service.close()
