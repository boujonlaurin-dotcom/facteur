"""Tests for EditorialLLMClient (Mistral API wrapper)."""

import json
from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import pytest

from app.services.editorial.llm_client import EditorialLLMClient


def _mock_settings(api_key: str = "test-key"):
    settings = MagicMock()
    settings.mistral_api_key = api_key
    return settings


def _make_response(content: str, status_code: int = 200) -> MagicMock:
    """Build a mock httpx.Response with Mistral chat completion format."""
    body = {
        "choices": [{"message": {"content": content}}],
        "usage": {"prompt_tokens": 100, "completion_tokens": 50},
    }
    resp = MagicMock(spec=httpx.Response)
    resp.status_code = status_code
    resp.json.return_value = body
    resp.raise_for_status = MagicMock()
    resp.text = json.dumps(body)
    return resp


class TestIsReady:
    def test_ready_with_api_key(self):
        with patch("app.services.editorial.llm_client.get_settings", return_value=_mock_settings("sk-123")):
            client = EditorialLLMClient()
        assert client.is_ready is True

    def test_not_ready_without_api_key(self):
        with patch("app.services.editorial.llm_client.get_settings", return_value=_mock_settings("")):
            client = EditorialLLMClient()
        assert client.is_ready is False


class TestChatJson:
    @pytest.fixture
    def client(self):
        with patch("app.services.editorial.llm_client.get_settings", return_value=_mock_settings("sk-test")):
            c = EditorialLLMClient()
        return c

    @pytest.mark.asyncio
    async def test_valid_json_response(self, client):
        expected = {"topics": [{"topic_id": "c1", "label": "Test"}]}
        resp = _make_response(json.dumps(expected))

        mock_http = AsyncMock()
        mock_http.post = AsyncMock(return_value=resp)
        client._client = mock_http

        result = await client.chat_json(system="sys", user_message="msg")
        assert result == expected
        mock_http.post.assert_awaited_once()

    @pytest.mark.asyncio
    async def test_strips_code_fences(self, client):
        expected = {"selected_index": 1, "reason": "Good match"}
        fenced = f"```json\n{json.dumps(expected)}\n```"
        resp = _make_response(fenced)

        mock_http = AsyncMock()
        mock_http.post = AsyncMock(return_value=resp)
        client._client = mock_http

        result = await client.chat_json(system="sys", user_message="msg")
        assert result == expected

    @pytest.mark.asyncio
    async def test_http_error_returns_none(self, client):
        error_resp = MagicMock(spec=httpx.Response)
        error_resp.status_code = 500
        error_resp.text = "Internal Server Error"
        error_resp.raise_for_status.side_effect = httpx.HTTPStatusError(
            "Server Error", request=MagicMock(), response=error_resp
        )

        mock_http = AsyncMock()
        mock_http.post = AsyncMock(return_value=error_resp)
        client._client = mock_http

        result = await client.chat_json(system="sys", user_message="msg")
        assert result is None

    @pytest.mark.asyncio
    async def test_invalid_json_returns_none(self, client):
        resp = _make_response("not valid json {{{")

        mock_http = AsyncMock()
        mock_http.post = AsyncMock(return_value=resp)
        client._client = mock_http

        result = await client.chat_json(system="sys", user_message="msg")
        assert result is None

    @pytest.mark.asyncio
    async def test_not_ready_returns_none(self):
        with patch("app.services.editorial.llm_client.get_settings", return_value=_mock_settings("")):
            client = EditorialLLMClient()

        result = await client.chat_json(system="sys", user_message="msg")
        assert result is None

    @pytest.mark.asyncio
    async def test_close(self, client):
        mock_http = AsyncMock()
        client._client = mock_http
        await client.close()
        mock_http.aclose.assert_awaited_once()
        assert client._client is None
