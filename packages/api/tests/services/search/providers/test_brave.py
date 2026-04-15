"""Tests for Brave Search provider."""

from unittest.mock import AsyncMock, patch

import httpx
import pytest

from app.services.search.providers.brave import BraveSearchProvider


@pytest.fixture
def brave_provider():
    """Create a BraveSearchProvider with a mocked API key."""
    with patch("app.services.search.providers.brave.get_settings") as mock_settings:
        mock_settings.return_value.brave_api_key = "test-key"
        provider = BraveSearchProvider()
    return provider


@pytest.fixture
def brave_provider_no_key():
    """Create a BraveSearchProvider without API key."""
    with patch("app.services.search.providers.brave.get_settings") as mock_settings:
        mock_settings.return_value.brave_api_key = ""
        provider = BraveSearchProvider()
    return provider


class TestBraveSearchProvider:
    @pytest.mark.asyncio
    async def test_search_not_ready(self, brave_provider_no_key):
        results = await brave_provider_no_key.search("test query")
        assert results == []
        assert not brave_provider_no_key.is_ready

    @pytest.mark.asyncio
    async def test_search_success(self, brave_provider):
        mock_response = httpx.Response(
            200,
            json={
                "web": {
                    "results": [
                        {
                            "url": "https://example.com",
                            "title": "Example",
                            "description": "An example site",
                        },
                        {
                            "url": "https://blog.example.com",
                            "title": "Example Blog",
                            "description": "A blog",
                        },
                    ]
                }
            },
            request=httpx.Request("GET", "https://api.search.brave.com"),
        )

        with patch("httpx.AsyncClient.get", new_callable=AsyncMock, return_value=mock_response):
            results = await brave_provider.search("example")

        assert len(results) == 2
        assert results[0]["url"] == "https://example.com"
        assert results[0]["title"] == "Example"

    @pytest.mark.asyncio
    async def test_search_429_graceful(self, brave_provider):
        mock_response = httpx.Response(
            429,
            request=httpx.Request("GET", "https://api.search.brave.com"),
        )

        with patch("httpx.AsyncClient.get", new_callable=AsyncMock) as mock_get:
            mock_get.side_effect = httpx.HTTPStatusError(
                "Rate limited", request=mock_response.request, response=mock_response
            )
            results = await brave_provider.search("test")

        assert results == []

    @pytest.mark.asyncio
    async def test_search_timeout_graceful(self, brave_provider):
        with patch("httpx.AsyncClient.get", new_callable=AsyncMock) as mock_get:
            mock_get.side_effect = httpx.TimeoutException("timeout")
            results = await brave_provider.search("test")

        assert results == []

    @pytest.mark.asyncio
    async def test_search_empty_results(self, brave_provider):
        mock_response = httpx.Response(
            200,
            json={"web": {"results": []}},
            request=httpx.Request("GET", "https://api.search.brave.com"),
        )

        with patch("httpx.AsyncClient.get", new_callable=AsyncMock, return_value=mock_response):
            results = await brave_provider.search("nonexistent")

        assert results == []
