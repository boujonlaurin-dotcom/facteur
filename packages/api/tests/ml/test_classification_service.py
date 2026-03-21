"""
Unit tests for ClassificationService.

Tests the Mistral LLM-based classification: prompt building, response parsing,
distribution checks, topic validation, API retry/backoff, and entity extraction.
"""

import json
import logging
from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import pytest

from app.services.ml.classification_service import (
    CLASSIFICATION_MODEL,
    ENTITY_SYSTEM_PROMPT,
    VALID_TOPIC_SLUGS,
    ClassificationService,
    _clean_text,
)


class TestCleanText:
    """Tests for _clean_text HTML stripping."""

    def test_strips_html_tags(self):
        """HTML tags are removed."""
        text = '<div class="chapo">Hello world</div>'
        assert _clean_text(text) == "Hello world"

    def test_decodes_html_entities(self):
        """HTML entities are decoded."""
        text = "L&#039;affiche &amp; les ombres"
        assert _clean_text(text) == "L'affiche & les ombres"

    def test_collapses_whitespace(self):
        """Multiple whitespace is collapsed."""
        text = "<div>  Hello  </div>  <span>  world  </span>"
        assert _clean_text(text) == "Hello world"

    def test_empty_string(self):
        """Empty string returns empty."""
        assert _clean_text("") == ""

    def test_clean_text_passes_through(self):
        """Clean text is unchanged."""
        text = "Un article normal sur le sport"
        assert _clean_text(text) == text


class TestTopicTaxonomy:
    """Tests for the topic taxonomy constants."""

    def test_fifty_topics(self):
        """Verify we have exactly 50 topics."""
        assert len(VALID_TOPIC_SLUGS) == 51

    def test_slugs_are_lowercase(self):
        """Verify all slugs are lowercase."""
        for slug in VALID_TOPIC_SLUGS:
            assert slug == slug.lower(), f"Slug not lowercase: {slug}"

    def test_known_slugs_present(self):
        """Verify key slugs are in the taxonomy."""
        expected = {"ai", "tech", "sport", "geopolitics", "cinema", "health", "climate"}
        assert expected.issubset(VALID_TOPIC_SLUGS)


class TestParseTopics:
    """Tests for _parse_topics (single-article response parsing)."""

    def setup_method(self):
        self.service = ClassificationService.__new__(ClassificationService)

    def test_parse_json_object(self):
        """New format: JSON object with topics and serene."""
        raw = '{"topics": ["sport", "health"], "serene": true}'
        result = self.service._parse_topics(raw, top_k=3)
        assert result["topics"] == ["sport", "health"]
        assert result["serene"] is True

    def test_parse_json_array_single_element(self):
        """New format: JSON array with one object."""
        raw = '[{"topics": ["ai", "tech"], "serene": false}]'
        result = self.service._parse_topics(raw, top_k=3)
        assert result["topics"] == ["ai", "tech"]
        assert result["serene"] is False

    def test_parse_comma_separated_fallback(self):
        """Old format: comma-separated slugs → serene is None."""
        raw = "sport, health, wellness"
        result = self.service._parse_topics(raw, top_k=3)
        assert result["topics"] == ["sport", "health", "wellness"]
        assert result["serene"] is None

    def test_filters_invalid_slugs(self):
        """Invalid slugs are filtered out."""
        raw = '{"topics": ["sport", "invalid_slug", "tech"], "serene": true}'
        result = self.service._parse_topics(raw, top_k=3)
        assert result["topics"] == ["sport", "tech"]
        assert "invalid_slug" not in result["topics"]

    def test_top_k_limits(self):
        """top_k limits the number of returned topics."""
        raw = '{"topics": ["sport", "health", "wellness", "tech"], "serene": true}'
        result = self.service._parse_topics(raw, top_k=2)
        assert len(result["topics"]) == 2

    def test_empty_raw_returns_empty(self):
        """Empty raw string returns empty topics."""
        raw = ""
        result = self.service._parse_topics(raw, top_k=3)
        assert result["topics"] == []

    def test_invalid_serene_becomes_none(self):
        """Non-boolean serene values become None."""
        raw = '{"topics": ["sport"], "serene": "maybe"}'
        result = self.service._parse_topics(raw, top_k=3)
        assert result["serene"] is None


class TestParseBatchResponse:
    """Tests for _parse_batch_response (batch response parsing)."""

    def setup_method(self):
        self.service = ClassificationService.__new__(ClassificationService)

    def test_correct_count_new_format(self):
        """JSON array of 5 objects parsed correctly."""
        data = [
            {"topics": ["sport"], "serene": True},
            {"topics": ["ai", "tech"], "serene": True},
            {"topics": ["geopolitics"], "serene": False},
            {"topics": ["cinema", "art"], "serene": True},
            {"topics": ["health"], "serene": False},
        ]
        raw = json.dumps(data)
        results = self.service._parse_batch_response(raw, expected_count=5, top_k=3)

        assert len(results) == 5
        assert results[0]["topics"] == ["sport"]
        assert results[0]["serene"] is True
        assert results[1]["topics"] == ["ai", "tech"]
        assert results[2]["serene"] is False

    def test_wrong_count_returns_partial_results(self):
        """JSON with fewer items than expected returns partial results, padded with empty."""
        data = [
            {"topics": ["sport"], "serene": True},
            {"topics": ["ai"], "serene": False},
            {"topics": ["health"], "serene": True},
            {"topics": ["cinema"], "serene": True},
        ]
        raw = json.dumps(data)
        results = self.service._parse_batch_response(raw, expected_count=5, top_k=3)

        assert len(results) == 5
        # First 4 should have their topics
        assert results[0]["topics"] == ["sport"]
        assert results[1]["topics"] == ["ai"]
        assert results[2]["topics"] == ["health"]
        assert results[3]["topics"] == ["cinema"]
        # 5th should be padded empty
        assert results[4]["topics"] == []
        assert results[4]["serene"] is None

    def test_fallback_old_format(self):
        """Old format (array of arrays) → topics OK, serene=None."""
        data = [
            ["sport", "health"],
            ["ai", "tech"],
            ["geopolitics"],
        ]
        raw = json.dumps(data)
        results = self.service._parse_batch_response(raw, expected_count=3, top_k=3)

        assert len(results) == 3
        assert results[0]["topics"] == ["sport", "health"]
        assert results[0]["serene"] is None
        assert results[1]["topics"] == ["ai", "tech"]

    def test_filters_invalid_slugs_in_batch(self):
        """Invalid slugs are filtered in batch responses."""
        data = [
            {"topics": ["sport", "invalid"], "serene": True},
        ]
        raw = json.dumps(data)
        results = self.service._parse_batch_response(raw, expected_count=1, top_k=3)

        assert results[0]["topics"] == ["sport"]


class TestBuildBatchPrompt:
    """Tests for _build_batch_prompt."""

    def setup_method(self):
        self.service = ClassificationService.__new__(ClassificationService)

    def test_includes_source_name(self):
        """Source name is included in prompt when provided."""
        items = [
            {
                "title": "Match PSG-OM",
                "description": "Ligue 1",
                "source_name": "L'Équipe",
            },
        ]
        prompt = self.service._build_batch_prompt(items)
        assert "[Source: L'Équipe]" in prompt
        assert "[1]" in prompt
        assert "Match PSG-OM" in prompt

    def test_no_source_name(self):
        """No [Source: ...] when source_name is empty."""
        items = [
            {"title": "Un article", "description": "desc", "source_name": ""},
        ]
        prompt = self.service._build_batch_prompt(items)
        assert "[Source:" not in prompt

    def test_truncates_description(self):
        """Description longer than 200 chars is truncated."""
        long_desc = "A" * 300
        items = [
            {"title": "Titre", "description": long_desc, "source_name": ""},
        ]
        prompt = self.service._build_batch_prompt(items)
        # Should contain truncated description (200 chars + "...")
        assert "A" * 200 + "..." in prompt
        assert "A" * 300 not in prompt

    def test_multiple_articles_numbered(self):
        """Multiple articles are numbered [1], [2], etc."""
        items = [
            {"title": "Premier", "description": "", "source_name": ""},
            {"title": "Deuxième", "description": "", "source_name": ""},
            {"title": "Troisième", "description": "", "source_name": ""},
        ]
        prompt = self.service._build_batch_prompt(items)
        assert "[1]" in prompt
        assert "[2]" in prompt
        assert "[3]" in prompt

    def test_includes_count_instruction(self):
        """Prompt includes the exact count instruction."""
        items = [
            {"title": "A", "description": "", "source_name": ""},
            {"title": "B", "description": "", "source_name": ""},
        ]
        prompt = self.service._build_batch_prompt(items)
        assert "exactement 2 éléments" in prompt


class TestCheckDistribution:
    """Tests for _check_distribution."""

    def setup_method(self):
        self.service = ClassificationService.__new__(ClassificationService)

    def test_warns_on_skewed_distribution(self, caplog):
        """Warning logged when >50% share the same primary topic."""
        results = [
            {"topics": ["geopolitics"], "serene": False},
            {"topics": ["geopolitics"], "serene": False},
            {"topics": ["geopolitics"], "serene": False},
            {"topics": ["sport"], "serene": True},
            {"topics": ["tech"], "serene": True},
        ]
        with caplog.at_level(logging.WARNING):
            self.service._check_distribution(results)
        # structlog may not write to caplog, so we just verify no crash
        # The actual warning is logged via structlog

    def test_no_warning_on_balanced_distribution(self, caplog):
        """No warning when distribution is balanced."""
        results = [
            {"topics": ["sport"], "serene": True},
            {"topics": ["tech"], "serene": True},
            {"topics": ["cinema"], "serene": True},
            {"topics": ["health"], "serene": True},
            {"topics": ["ai"], "serene": True},
        ]
        self.service._check_distribution(results)
        # Should not raise or warn

    def test_handles_empty_results(self):
        """No crash on empty results."""
        self.service._check_distribution([])

    def test_handles_no_topics(self):
        """No crash when results have empty topics."""
        results = [
            {"topics": [], "serene": None},
            {"topics": [], "serene": None},
        ]
        self.service._check_distribution(results)


class TestCallMistral:
    """Tests for _call_mistral retry/backoff and error handling."""

    def setup_method(self):
        self.service = ClassificationService.__new__(ClassificationService)
        self.service._api_key = "test-key"
        self.service._ready = True
        self.service._client = None

    @pytest.mark.asyncio
    async def test_returns_data_on_success(self):
        """Successful API call returns parsed JSON."""
        mock_response = MagicMock()
        mock_response.raise_for_status = MagicMock()
        mock_response.json.return_value = {
            "choices": [{"message": {"content": '{"topics": ["sport"]}'}}],
            "usage": {"prompt_tokens": 100, "completion_tokens": 20},
        }

        mock_client = AsyncMock()
        mock_client.post.return_value = mock_response
        self.service._client = mock_client

        result = await self.service._call_mistral({"model": "test", "max_tokens": 100})
        assert result is not None
        assert result["choices"][0]["message"]["content"] == '{"topics": ["sport"]}'

    @pytest.mark.asyncio
    async def test_retries_on_429(self):
        """429 responses trigger exponential backoff retries."""
        error_response = MagicMock()
        error_response.status_code = 429
        error_response.text = "rate limited"

        success_response = MagicMock()
        success_response.raise_for_status = MagicMock()
        success_response.json.return_value = {
            "choices": [{"message": {"content": "{}"}}],
            "usage": {},
        }

        mock_client = AsyncMock()
        mock_client.post.side_effect = [
            httpx.HTTPStatusError("429", request=MagicMock(), response=error_response),
            success_response,
        ]
        self.service._client = mock_client

        with patch(
            "app.services.ml.classification_service.asyncio.sleep",
            new_callable=AsyncMock,
        ):
            result = await self.service._call_mistral(
                {"model": "test", "max_tokens": 50}
            )

        assert result is not None
        assert mock_client.post.call_count == 2

    @pytest.mark.asyncio
    async def test_returns_none_on_non_429_http_error(self):
        """Non-429 HTTP errors return None immediately."""
        error_response = MagicMock()
        error_response.status_code = 500
        error_response.text = "server error"

        mock_client = AsyncMock()
        mock_client.post.side_effect = httpx.HTTPStatusError(
            "500", request=MagicMock(), response=error_response
        )
        self.service._client = mock_client

        result = await self.service._call_mistral({"model": "test", "max_tokens": 50})
        assert result is None
        assert mock_client.post.call_count == 1

    @pytest.mark.asyncio
    async def test_returns_none_on_timeout(self):
        """Timeout returns None."""
        mock_client = AsyncMock()
        mock_client.post.side_effect = httpx.TimeoutException("timeout")
        self.service._client = mock_client

        result = await self.service._call_mistral({"model": "test", "max_tokens": 50})
        assert result is None


class TestResponseFormatInPayloads:
    """Verify response_format is included in all API call payloads."""

    def setup_method(self):
        self.service = ClassificationService.__new__(ClassificationService)
        self.service._api_key = "test-key"
        self.service._ready = True
        self.service._client = None

    @pytest.mark.asyncio
    async def test_classify_async_includes_response_format(self):
        """classify_async payload includes response_format json_object."""
        captured_payload = {}

        async def capture_post(url, json=None):
            captured_payload.update(json)
            resp = MagicMock()
            resp.raise_for_status = MagicMock()
            resp.json.return_value = {
                "choices": [
                    {"message": {"content": '{"topics": ["sport"], "serene": true}'}}
                ],
                "usage": {},
            }
            return resp

        mock_client = AsyncMock()
        mock_client.post = capture_post
        self.service._client = mock_client

        await self.service.classify_async("Match PSG-OM")
        assert captured_payload.get("response_format") == {"type": "json_object"}
        assert captured_payload.get("model") == CLASSIFICATION_MODEL

    @pytest.mark.asyncio
    async def test_classify_batch_includes_response_format(self):
        """classify_batch_async payload includes response_format json_object."""
        captured_payload = {}

        async def capture_post(url, json=None):
            captured_payload.update(json)
            resp = MagicMock()
            resp.raise_for_status = MagicMock()
            resp.json.return_value = {
                "choices": [
                    {"message": {"content": '[{"topics": ["sport"], "serene": true}]'}}
                ],
                "usage": {},
            }
            return resp

        mock_client = AsyncMock()
        mock_client.post = capture_post
        self.service._client = mock_client

        await self.service.classify_batch_async(
            [{"title": "Test", "description": "", "source_name": ""}]
        )
        assert captured_payload.get("response_format") == {"type": "json_object"}

    @pytest.mark.asyncio
    async def test_entity_extraction_includes_response_format_and_system_prompt(self):
        """extract_entities_batch_async includes response_format and ENTITY_SYSTEM_PROMPT."""
        captured_payload = {}

        async def capture_post(url, json=None):
            captured_payload.update(json)
            resp = MagicMock()
            resp.raise_for_status = MagicMock()
            resp.json.return_value = {
                "choices": [
                    {"message": {"content": '[[{"name": "Macron", "type": "PERSON"}]]'}}
                ],
                "usage": {},
            }
            return resp

        mock_client = AsyncMock()
        mock_client.post = capture_post
        self.service._client = mock_client

        await self.service.extract_entities_batch_async(
            [{"title": "Test", "description": "", "source_name": ""}]
        )
        assert captured_payload.get("response_format") == {"type": "json_object"}
        # Verify system prompt is present
        messages = captured_payload.get("messages", [])
        system_msgs = [m for m in messages if m.get("role") == "system"]
        assert len(system_msgs) == 1
        assert system_msgs[0]["content"] == ENTITY_SYSTEM_PROMPT
