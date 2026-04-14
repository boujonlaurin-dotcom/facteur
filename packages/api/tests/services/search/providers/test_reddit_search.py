"""Tests for Reddit search provider."""

from unittest.mock import AsyncMock, patch

import httpx
import pytest

from app.services.search.providers.reddit_search import RedditSearchProvider


@pytest.fixture
def reddit_provider():
    return RedditSearchProvider()


class TestRedditSearchProvider:
    @pytest.mark.asyncio
    async def test_search_success(self, reddit_provider):
        mock_response = httpx.Response(
            200,
            json={
                "data": {
                    "children": [
                        {
                            "data": {
                                "display_name": "france",
                                "public_description": "La France et les Français",
                                "subscribers": 1200000,
                            }
                        },
                        {
                            "data": {
                                "display_name": "french",
                                "public_description": "Learning French",
                                "subscribers": 300000,
                            }
                        },
                    ]
                }
            },
            request=httpx.Request("GET", "https://www.reddit.com"),
        )

        with patch("httpx.AsyncClient.get", new_callable=AsyncMock, return_value=mock_response):
            results = await reddit_provider.search("france")

        assert len(results) == 2
        assert results[0]["name"] == "r/france"
        assert results[0]["feed_url"] == "https://www.reddit.com/r/france/.rss"
        assert results[0]["subscribers"] == 1200000

    @pytest.mark.asyncio
    async def test_search_empty_results(self, reddit_provider):
        mock_response = httpx.Response(
            200,
            json={"data": {"children": []}},
            request=httpx.Request("GET", "https://www.reddit.com"),
        )

        with patch("httpx.AsyncClient.get", new_callable=AsyncMock, return_value=mock_response):
            results = await reddit_provider.search("xyznonexistent123")

        assert results == []

    @pytest.mark.asyncio
    async def test_search_http_error(self, reddit_provider):
        mock_response = httpx.Response(
            503,
            request=httpx.Request("GET", "https://www.reddit.com"),
        )

        with patch("httpx.AsyncClient.get", new_callable=AsyncMock) as mock_get:
            mock_get.side_effect = httpx.HTTPStatusError(
                "Service Unavailable",
                request=mock_response.request,
                response=mock_response,
            )
            results = await reddit_provider.search("test")

        assert results == []

    @pytest.mark.asyncio
    async def test_search_timeout(self, reddit_provider):
        with patch("httpx.AsyncClient.get", new_callable=AsyncMock) as mock_get:
            mock_get.side_effect = httpx.TimeoutException("timeout")
            results = await reddit_provider.search("test")

        assert results == []

    @pytest.mark.asyncio
    async def test_skips_entries_without_name(self, reddit_provider):
        mock_response = httpx.Response(
            200,
            json={
                "data": {
                    "children": [
                        {"data": {"display_name": "", "subscribers": 100}},
                        {"data": {"display_name": "valid", "subscribers": 200}},
                    ]
                }
            },
            request=httpx.Request("GET", "https://www.reddit.com"),
        )

        with patch("httpx.AsyncClient.get", new_callable=AsyncMock, return_value=mock_response):
            results = await reddit_provider.search("test")

        assert len(results) == 1
        assert results[0]["name"] == "r/valid"
