"""Tests for smart source search orchestrator."""

import pytest

from app.services.search.smart_source_search import (
    _classify_query,
    _compute_score,
)
from app.services.search.cache import hash_query, normalize_query


# ─── classify_query tests ─────────────────────────────────────────


class TestClassifyQuery:
    def test_classify_url_with_protocol(self):
        assert _classify_query("https://example.com") == "url_like"

    def test_classify_url_without_protocol(self):
        assert _classify_query("example.com") == "url_like"

    def test_classify_url_with_path(self):
        assert _classify_query("blog.example.com/feed") == "url_like"

    def test_classify_youtube_handle(self):
        assert _classify_query("@fireship") == "youtube_handle"

    def test_classify_youtube_handle_with_dots(self):
        assert _classify_query("@ben.thompson") == "youtube_handle"

    def test_classify_reddit_subreddit(self):
        assert _classify_query("r/france") == "reddit_sub"

    def test_classify_reddit_subreddit_case_insensitive(self):
        assert _classify_query("R/Python") == "reddit_sub"

    def test_classify_free_text(self):
        assert _classify_query("lenny newsletter") == "free_text"

    def test_classify_free_text_single_word(self):
        assert _classify_query("stratechery") == "free_text"

    def test_classify_free_text_with_spaces(self):
        assert _classify_query("  la newsletter finance  ") == "free_text"


# ─── compute_score tests ─────────────────────────────────────────


class TestComputeScore:
    def test_catalog_curated_high_score(self):
        score = _compute_score(
            layer="catalog",
            in_catalog=True,
            is_curated=True,
            follower_count=50,
            freshness_days=2.0,
            type_match=True,
            theme_affinity=True,
        )
        # confidence=1.0*0.4 + popularity=0.5*0.25 + freshness~0.93*0.15 + type=0.1 + theme=0.1
        assert score > 0.8

    def test_mistral_low_score(self):
        score = _compute_score(
            layer="mistral",
            in_catalog=False,
            is_curated=False,
            follower_count=0,
            freshness_days=None,
            type_match=False,
            theme_affinity=False,
        )
        # confidence=0.5*0.4 + popularity=0 + freshness=0.5*0.15 + 0 + 0
        assert score < 0.4

    def test_brave_medium_score(self):
        score = _compute_score(
            layer="brave",
            in_catalog=False,
            is_curated=False,
            follower_count=0,
            freshness_days=5.0,
            type_match=True,
            theme_affinity=False,
        )
        assert 0.3 < score < 0.7

    def test_freshness_very_old(self):
        score_old = _compute_score(
            "catalog", True, True, 0, 60.0, False, False
        )
        score_new = _compute_score(
            "catalog", True, True, 0, 1.0, False, False
        )
        assert score_new > score_old

    def test_score_components_sum_correctly(self):
        # Perfect score: all maximums
        score = _compute_score(
            layer="catalog",
            in_catalog=True,
            is_curated=True,
            follower_count=200,  # capped at 100 → 1.0
            freshness_days=0,  # → 1.0
            type_match=True,
            theme_affinity=True,
        )
        # 0.4*1.0 + 0.25*1.0 + 0.15*1.0 + 0.1*1.0 + 0.1*1.0 = 1.0
        assert abs(score - 1.0) < 0.01


# ─── normalize + hash tests ──────────────────────────────────────


class TestNormalizeAndHash:
    def test_normalize_lowercase(self):
        assert normalize_query("Lenny Newsletter") == "lenny newsletter"

    def test_normalize_strip(self):
        assert normalize_query("  hello  ") == "hello"

    def test_normalize_collapse_whitespace(self):
        assert normalize_query("hello   world") == "hello world"

    def test_hash_deterministic(self):
        h1 = hash_query("lenny newsletter")
        h2 = hash_query("  Lenny  Newsletter  ")
        assert h1 == h2

    def test_hash_different_queries(self):
        h1 = hash_query("lenny")
        h2 = hash_query("newsletter")
        assert h1 != h2


# ─── Dedup logic test ────────────────────────────────────────────


class TestDedup:
    def test_dedup_by_feed_url(self):
        """Results with same feed_url should be deduplicated in pipeline."""
        seen: set[str] = set()
        results = []
        candidates = [
            {"feed_url": "https://example.com/feed", "name": "A", "score": 0.9},
            {"feed_url": "https://example.com/feed", "name": "B", "score": 0.8},
            {"feed_url": "https://other.com/feed", "name": "C", "score": 0.7},
        ]
        for r in candidates:
            if r["feed_url"] not in seen:
                seen.add(r["feed_url"])
                results.append(r)
        assert len(results) == 2
        assert results[0]["name"] == "A"
        assert results[1]["name"] == "C"
