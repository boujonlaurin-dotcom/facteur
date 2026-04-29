"""Tests for smart source search orchestrator."""

import pytest

from app.services.search.cache import hash_query, normalize_query
from app.services.search.smart_source_search import (
    _classify_query,
    _compute_score,
    _is_strong_catalog_match,
)

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
        score_old = _compute_score("catalog", True, True, 0, 60.0, False, False)
        score_new = _compute_score("catalog", True, True, 0, 1.0, False, False)
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


# ─── Strong match predicate ──────────────────────────────────────


class TestStrongCatalogMatch:
    def test_exact_name(self):
        assert _is_strong_catalog_match({"name": "Mediapart"}, "mediapart") is True

    def test_case_insensitive_via_normalization(self):
        assert _is_strong_catalog_match({"name": "MEDIAPART"}, "mediapart") is True

    def test_prefix_with_trailing_word(self):
        assert (
            _is_strong_catalog_match({"name": "Le Monde diplomatique"}, "le monde")
            is True
        )

    def test_word_boundary_middle(self):
        assert _is_strong_catalog_match({"name": "Chaîne YouTube Arte"}, "arte") is True

    def test_substring_only_rejected(self):
        # "le" is a substring of "lenny" but not a word — must not match.
        assert _is_strong_catalog_match({"name": "Lenny Newsletter"}, "le") is False

    def test_empty_query(self):
        assert _is_strong_catalog_match({"name": "Mediapart"}, "") is False

    def test_missing_name(self):
        assert _is_strong_catalog_match({}, "mediapart") is False


# ─── Cache key differentiation ──────────────────────────────────


class TestCacheKeyDifferentiation:
    def test_content_type_changes_hash(self):
        assert hash_query("mediapart") != hash_query("mediapart", "article")

    def test_expand_changes_hash(self):
        assert hash_query("mediapart") != hash_query("mediapart", None, True)

    def test_content_type_values_differ(self):
        assert hash_query("fireship", "youtube") != hash_query("fireship", "article")

    def test_same_params_same_hash(self):
        assert hash_query("x", "youtube", True) == hash_query("x", "youtube", True)


# ─── Accent stripping in normalize_query ────────────────────────


class TestNormalizeQueryAccents:
    def test_strips_french_accents(self):
        assert normalize_query("Arrêt sur Images") == "arret sur images"

    def test_strips_grave_accent(self):
        assert normalize_query("Lèvres") == "levres"

    def test_keeps_ascii_unchanged(self):
        assert normalize_query("Mediapart") == "mediapart"


# ─── Listicle / denylist helpers ────────────────────────────────


class TestListicleFilters:
    def test_feedspot_host_blocked(self):
        from app.services.search.providers.denylist import is_listicle_host

        assert is_listicle_host("https://blog.feedspot.com/best") is True

    def test_floridapolitics_host_blocked(self):
        from app.services.search.providers.denylist import is_listicle_host

        assert is_listicle_host("https://floridapolitics.com/archives/123") is True

    def test_real_publisher_host_allowed(self):
        from app.services.search.providers.denylist import is_listicle_host

        assert is_listicle_host("https://www.lemonde.fr/article.html") is False

    def test_top_n_title_blocked(self):
        from app.services.search.providers.denylist import is_listicle_title

        assert is_listicle_title("60 Best Political News RSS Feeds") is True
        assert is_listicle_title("Top 100 Political RSS Feeds") is True

    def test_real_article_title_allowed(self):
        from app.services.search.providers.denylist import is_listicle_title

        assert is_listicle_title("Le Monde — édition du soir") is False


# ─── Root URL helper + finalize drops no-feed results ───────────


class TestRootUrl:
    def test_strips_path(self):
        from app.services.search.smart_source_search import (
            SmartSourceSearchService,
        )

        assert (
            SmartSourceSearchService._root_url("https://www.lemonde.fr/a/b.html")
            == "https://www.lemonde.fr"
        )

    def test_unparsable_returns_none(self):
        from app.services.search.smart_source_search import (
            SmartSourceSearchService,
        )

        assert SmartSourceSearchService._root_url("not a url") is None


# ─── _detect_with_root_fallback: root-first ──────────────────────


class TestDetectWithRootFallback:
    @pytest.mark.asyncio
    async def test_resolves_root_when_root_has_feed(self, monkeypatch):
        """For a normal article URL the root is probed (path-level platforms
        are the exception, not the rule)."""
        from app.services.search.smart_source_search import (
            SmartSourceSearchService,
        )

        svc = SmartSourceSearchService.__new__(SmartSourceSearchService)
        seen: list[str] = []

        async def fake_cached_detect(self, target):
            seen.append(target)
            if target == "https://www.lemonde.fr":
                return {"feed_url": "https://www.lemonde.fr/rss/une.xml"}
            return None

        monkeypatch.setattr(
            SmartSourceSearchService,
            "_cached_detect_feed",
            fake_cached_detect,
        )
        out = await svc._detect_with_root_fallback(
            "https://www.lemonde.fr/section/article-123.html"
        )
        assert seen == ["https://www.lemonde.fr"]
        assert out == (
            "https://www.lemonde.fr",
            {"feed_url": "https://www.lemonde.fr/rss/une.xml"},
        )

    @pytest.mark.asyncio
    async def test_youtube_uses_path_level_url(self, monkeypatch):
        """YouTube channel feeds live at /@handle, not at the host root."""
        from app.services.search.smart_source_search import (
            SmartSourceSearchService,
        )

        svc = SmartSourceSearchService.__new__(SmartSourceSearchService)
        seen: list[str] = []

        async def fake_cached_detect(self, target):
            seen.append(target)
            return {"feed_url": "https://www.youtube.com/feeds/videos.xml?channel_id=X"}

        monkeypatch.setattr(
            SmartSourceSearchService,
            "_cached_detect_feed",
            fake_cached_detect,
        )
        out = await svc._detect_with_root_fallback(
            "https://www.youtube.com/@HugoDecrypte"
        )
        assert seen == ["https://www.youtube.com/@HugoDecrypte"]
        assert out is not None

    @pytest.mark.asyncio
    async def test_returns_none_when_root_has_no_feed(self, monkeypatch):
        from app.services.search.smart_source_search import (
            SmartSourceSearchService,
        )

        svc = SmartSourceSearchService.__new__(SmartSourceSearchService)

        async def fake_cached_detect(self, target):
            return None

        monkeypatch.setattr(
            SmartSourceSearchService,
            "_cached_detect_feed",
            fake_cached_detect,
        )
        assert (
            await svc._detect_with_root_fallback(
                "https://no-feed-host.example.com/path"
            )
            is None
        )


# ─── Host-level cache helpers ─────────────────────────────────────


class TestCacheKey:
    def test_normal_host_keyed_by_host(self):
        from app.services.search.smart_source_search import (
            SmartSourceSearchService,
        )

        assert (
            SmartSourceSearchService._cache_key(
                "https://www.lemonde.fr/article-123.html"
            )
            == "www.lemonde.fr"
        )

    def test_youtube_channel_keyed_by_host_plus_path(self):
        from app.services.search.smart_source_search import (
            SmartSourceSearchService,
        )

        # Distinct YouTube channels must NOT collide on the host root.
        a = SmartSourceSearchService._cache_key("https://www.youtube.com/@HugoDecrypte")
        b = SmartSourceSearchService._cache_key("https://www.youtube.com/@LeMedia")
        assert a == "www.youtube.com/@hugodecrypte"
        assert b == "www.youtube.com/@lemedia"
        assert a != b

    def test_unparsable_returns_none(self):
        from app.services.search.smart_source_search import (
            SmartSourceSearchService,
        )

        assert SmartSourceSearchService._cache_key("not a url") is None


class TestLooksFrench:
    def test_accent_triggers(self):
        from app.services.search.smart_source_search import _looks_french

        assert _looks_french("café société") is True

    def test_french_token_triggers(self):
        from app.services.search.smart_source_search import _looks_french

        assert _looks_french("le monde") is True

    def test_english_query_no_match(self):
        from app.services.search.smart_source_search import _looks_french

        assert _looks_french("political news") is False
