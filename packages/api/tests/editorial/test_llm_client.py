"""Tests for EditorialLLMClient (Mistral API wrapper)."""

import json
from contextlib import asynccontextmanager
from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import pytest

from app.services.editorial.llm_client import EditorialLLMClient


def _error_response(status_code: int) -> MagicMock:
    """Mock httpx.Response whose raise_for_status raises HTTPStatusError."""
    resp = MagicMock(spec=httpx.Response)
    resp.status_code = status_code
    resp.text = f"error {status_code}"
    resp.raise_for_status.side_effect = httpx.HTTPStatusError(
        f"{status_code}", request=MagicMock(), response=resp
    )
    return resp


class _SpyLimiter:
    """Stand-in for the shared limiter: counts how often `slot()` is entered."""

    def __init__(self) -> None:
        self.slot_calls = 0

    def slot(self):
        self.slot_calls += 1
        return self._cm()

    @asynccontextmanager
    async def _cm(self):
        yield


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
        with patch(
            "app.services.editorial.llm_client.get_settings",
            return_value=_mock_settings("sk-123"),
        ):
            client = EditorialLLMClient()
        assert client.is_ready is True

    def test_not_ready_without_api_key(self):
        with patch(
            "app.services.editorial.llm_client.get_settings",
            return_value=_mock_settings(""),
        ):
            client = EditorialLLMClient()
        assert client.is_ready is False


class TestChatJson:
    @pytest.fixture
    def client(self):
        with patch(
            "app.services.editorial.llm_client.get_settings",
            return_value=_mock_settings("sk-test"),
        ):
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
        with patch(
            "app.services.editorial.llm_client.get_settings",
            return_value=_mock_settings(""),
        ):
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


def _ready_client() -> EditorialLLMClient:
    with patch(
        "app.services.editorial.llm_client.get_settings",
        return_value=_mock_settings("sk-test"),
    ):
        return EditorialLLMClient()


class TestChatText:
    @pytest.fixture
    def client(self):
        return _ready_client()

    @pytest.mark.asyncio
    async def test_returns_text_on_success(self, client):
        resp = _make_response("Bonjour le monde")
        mock_http = AsyncMock()
        mock_http.post = AsyncMock(return_value=resp)
        client._client = mock_http

        result = await client.chat_text(system="sys", user_message="msg")
        assert result == "Bonjour le monde"
        mock_http.post.assert_awaited_once()

    @pytest.mark.asyncio
    async def test_retries_on_429_then_succeeds(self, client):
        ok = _make_response("rétabli")
        mock_http = AsyncMock()
        mock_http.post = AsyncMock(side_effect=[_error_response(429), ok])
        client._client = mock_http

        with patch(
            "app.services.editorial.llm_client.asyncio.sleep", new_callable=AsyncMock
        ):
            result = await client.chat_text(system="sys", user_message="msg")

        assert result == "rétabli"
        assert mock_http.post.await_count == 2

    @pytest.mark.asyncio
    async def test_returns_none_after_exhausting_retries(self, client):
        mock_http = AsyncMock()
        mock_http.post = AsyncMock(return_value=_error_response(503))
        client._client = mock_http

        with patch(
            "app.services.editorial.llm_client.asyncio.sleep", new_callable=AsyncMock
        ):
            result = await client.chat_text(system="sys", user_message="msg")

        assert result is None
        assert mock_http.post.await_count == 3  # initial + 2 retries


class TestTokenCapture:
    @pytest.fixture
    def client(self):
        return _ready_client()

    @pytest.mark.asyncio
    async def test_chat_json_records_tokens(self, client):
        resp = _make_response(json.dumps({"ok": True}))
        mock_http = AsyncMock()
        mock_http.post = AsyncMock(return_value=resp)
        client._client = mock_http

        with patch(
            "app.services.observability.usage_recorder.record_api_call",
            new_callable=AsyncMock,
        ) as rec:
            await client.chat_json(system="sys", user_message="msg")

        kwargs = rec.await_args.kwargs
        assert kwargs["prompt_tokens"] == 100
        assert kwargs["completion_tokens"] == 50

    @pytest.mark.asyncio
    async def test_chat_text_records_tokens(self, client):
        resp = _make_response("texte")
        mock_http = AsyncMock()
        mock_http.post = AsyncMock(return_value=resp)
        client._client = mock_http

        with patch(
            "app.services.observability.usage_recorder.record_api_call",
            new_callable=AsyncMock,
        ) as rec:
            await client.chat_text(system="sys", user_message="msg")

        kwargs = rec.await_args.kwargs
        assert kwargs["prompt_tokens"] == 100
        assert kwargs["completion_tokens"] == 50


class TestRateLimiterGating:
    @pytest.fixture
    def client(self):
        return _ready_client()

    @pytest.mark.asyncio
    async def test_large_model_goes_through_limiter(self, client):
        spy = _SpyLimiter()
        mock_http = AsyncMock()
        mock_http.post = AsyncMock(return_value=_make_response(json.dumps({})))
        client._client = mock_http

        with patch(
            "app.services.editorial.llm_client._get_large_limiter", return_value=spy
        ):
            await client.chat_json(
                system="s", user_message="m", model="mistral-large-latest"
            )
        assert spy.slot_calls == 1

    @pytest.mark.asyncio
    async def test_small_model_bypasses_limiter(self, client):
        spy = _SpyLimiter()
        mock_http = AsyncMock()
        mock_http.post = AsyncMock(return_value=_make_response(json.dumps({})))
        client._client = mock_http

        with patch(
            "app.services.editorial.llm_client._get_large_limiter", return_value=spy
        ):
            await client.chat_json(
                system="s", user_message="m", model="mistral-small-latest"
            )
        assert spy.slot_calls == 0

    @pytest.mark.asyncio
    async def test_kill_switch_bypasses_limiter(self, client):
        spy = _SpyLimiter()
        mock_http = AsyncMock()
        mock_http.post = AsyncMock(return_value=_make_response(json.dumps({})))
        client._client = mock_http

        disabled = _mock_settings("sk-test")
        disabled.mistral_rate_limit_enabled = False
        with (
            patch(
                "app.services.editorial.llm_client._get_large_limiter", return_value=spy
            ),
            patch(
                "app.services.editorial.llm_client.get_settings", return_value=disabled
            ),
        ):
            await client.chat_json(
                system="s", user_message="m", model="mistral-large-latest"
            )
        assert spy.slot_calls == 0
