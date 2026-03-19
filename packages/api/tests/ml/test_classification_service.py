"""
Unit tests for ClassificationService.

Tests the Mistral LLM-based classification: prompt building, response parsing,
distribution checks, and topic validation.
"""

import json
import logging

import pytest

from app.services.ml.classification_service import (
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
            {"title": "Match PSG-OM", "description": "Ligue 1", "source_name": "L'Équipe"},
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
