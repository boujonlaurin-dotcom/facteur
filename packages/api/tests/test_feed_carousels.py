"""Tests unitaires pour _build_carousels — promotion overflow → carrousels."""

import json
import pytest
from collections import namedtuple
from uuid import uuid4, UUID
from unittest.mock import MagicMock, AsyncMock

from app.services.recommendation_service import RecommendationService


class MockSource:
    def __init__(self, name="Source A", source_id=None, theme="tech"):
        self.id = source_id or uuid4()
        self.name = name
        self.logo_url = None
        self.theme = theme


class MockContent:
    def __init__(
        self,
        title="Article",
        source=None,
        entities=None,
        content_id=None,
        content_type="article",
    ):
        self.id = content_id or uuid4()
        self.title = title
        self.source = source or MockSource()
        self.source_id = self.source.id
        self.entities = entities or []
        self.content_type = content_type


def _make_entity_group(
    entity_name: str,
    hidden_count: int,
    representative: MockContent,
    hidden_articles: list[MockContent],
    num_sources: int = 1,
):
    """Helper: build an entity overflow dict matching the real format."""
    sources = []
    for i in range(num_sources):
        sources.append({
            "source_id": uuid4(),
            "source_name": f"Source {i}",
            "source_logo_url": None,
            "article_count": max(1, hidden_count // num_sources),
        })

    # Add entity JSON to representative for display name resolution
    entity_json = json.dumps({"name": entity_name.title(), "type": "PERSON"})
    representative.entities = [entity_json]
    for a in hidden_articles:
        a.entities = [entity_json]

    return {
        "entity_name": entity_name.lower(),
        "display_label": f"{entity_name.title()} — {hidden_count} articles",
        "hidden_count": hidden_count,
        "hidden_ids": [a.id for a in hidden_articles],
        "representative_id": representative.id,
        "sources": sources,
    }


def _make_keyword_group(
    keyword: str,
    hidden_count: int,
    representative: MockContent,
    hidden_articles: list[MockContent],
    is_custom_topic: bool = False,
    num_sources: int = 1,
):
    """Helper: build a keyword overflow dict matching the real format."""
    sources = []
    for i in range(num_sources):
        sources.append({
            "source_id": uuid4(),
            "source_name": f"Source {i}",
            "source_logo_url": None,
            "article_count": max(1, hidden_count // num_sources),
        })
    return {
        "keyword": keyword.title(),
        "filter_keyword": keyword.lower(),
        "display_label": f"{keyword.title()} — {hidden_count} articles",
        "hidden_count": hidden_count,
        "hidden_ids": [a.id for a in hidden_articles],
        "representative_id": representative.id,
        "sources": sources,
        "is_custom_topic": is_custom_topic,
    }


def _setup_service():
    """Create a RecommendationService with mocked session."""
    session = AsyncMock()
    service = RecommendationService(session)
    return service


# ================================================================
# Phase A tests (overflow-based carousels)
# ================================================================


class TestBuildCarouselsHot:
    @pytest.mark.asyncio
    async def test_hot_carousel_from_entity_overflow(self):
        service = _setup_service()
        rep = MockContent(title="Trump article")
        hidden = [MockContent(title=f"Trump {i}") for i in range(4)]
        pre_regroup_map = {a.id: a for a in [rep] + hidden}

        service.entity_overflow = [
            _make_entity_group("trump", 4, rep, hidden)
        ]
        service.keyword_overflow = []

        result_feed = [MockContent(title="Other article")]
        result, carousels = await service._build_carousels(result_feed, pre_regroup_map)

        assert len(carousels) == 1
        c = carousels[0]
        assert c["carousel_type"] == "hot"
        assert "Trump" in c["title"]
        assert c["emoji"] == "\U0001f534"
        assert c["position"] == 5
        assert len(c["items"]) == 5  # rep + 4 hidden
        assert len(c["badges"]) == len(c["items"])
        assert c["badges"][0]["code"] == "actu_chaude"

    @pytest.mark.asyncio
    async def test_hot_carousel_works_with_2_hidden(self):
        """Min 3 items = rep + 2 hidden → should create carousel."""
        service = _setup_service()
        rep = MockContent(title="Trump article")
        hidden = [MockContent(title="Trump 1"), MockContent(title="Trump 2")]
        pre_regroup_map = {a.id: a for a in [rep] + hidden}

        service.entity_overflow = [
            _make_entity_group("trump", 2, rep, hidden)
        ]
        service.keyword_overflow = []

        result, carousels = await service._build_carousels([], pre_regroup_map)
        assert len(carousels) == 1
        assert len(carousels[0]["items"]) == 3  # rep + 2 hidden

    @pytest.mark.asyncio
    async def test_hot_carousel_requires_min_2_hidden(self):
        """1 hidden + rep = 2 items < MIN_CAROUSEL_ITEMS(3) → no carousel."""
        service = _setup_service()
        rep = MockContent(title="Trump article")
        hidden = [MockContent(title="Trump 1")]
        pre_regroup_map = {a.id: a for a in [rep] + hidden}

        service.entity_overflow = [
            _make_entity_group("trump", 1, rep, hidden)
        ]
        service.keyword_overflow = []

        result, carousels = await service._build_carousels([], pre_regroup_map)
        assert len(carousels) == 0

    @pytest.mark.asyncio
    async def test_representative_included_in_carousel(self):
        service = _setup_service()
        rep = MockContent(title="Trump main")
        hidden = [MockContent(title=f"Trump {i}") for i in range(3)]
        pre_regroup_map = {a.id: a for a in [rep] + hidden}

        service.entity_overflow = [
            _make_entity_group("trump", 3, rep, hidden)
        ]
        service.keyword_overflow = []

        _, carousels = await service._build_carousels([], pre_regroup_map)
        assert len(carousels) == 1
        item_ids = {item.id for item in carousels[0]["items"]}
        assert rep.id in item_ids


class TestBuildCarouselsFavorite:
    @pytest.mark.asyncio
    async def test_favorite_from_custom_topic(self):
        service = _setup_service()
        rep = MockContent(title="Startups article")
        hidden = [MockContent(title=f"Startups {i}") for i in range(3)]
        pre_regroup_map = {a.id: a for a in [rep] + hidden}

        service.entity_overflow = []
        service.keyword_overflow = [
            _make_keyword_group("startups", 3, rep, hidden, is_custom_topic=True)
        ]

        _, carousels = await service._build_carousels([], pre_regroup_map)
        assert len(carousels) == 1
        c = carousels[0]
        assert c["carousel_type"] == "favorite"
        assert "Startups" in c["title"]
        assert c["badges"][0]["code"] == "focus_topic"

    @pytest.mark.asyncio
    async def test_no_favorite_if_not_custom_topic(self):
        service = _setup_service()
        rep = MockContent(title="Article")
        hidden = [MockContent(title=f"Article {i}") for i in range(3)]
        pre_regroup_map = {a.id: a for a in [rep] + hidden}

        service.entity_overflow = []
        service.keyword_overflow = [
            _make_keyword_group("generic", 3, rep, hidden, is_custom_topic=False)
        ]

        _, carousels = await service._build_carousels([], pre_regroup_map)
        # No favorite carousel for non-custom topics
        assert not any(c["carousel_type"] == "favorite" for c in carousels)


class TestBuildCarouselsDeep:
    @pytest.mark.asyncio
    async def test_deep_carousel_multi_source(self):
        service = _setup_service()
        rep = MockContent(title="Iran article")
        hidden = [MockContent(title=f"Iran {i}") for i in range(3)]
        pre_regroup_map = {a.id: a for a in [rep] + hidden}

        service.entity_overflow = [
            _make_entity_group("iran", 3, rep, hidden, num_sources=3)
        ]
        service.keyword_overflow = []

        _, carousels = await service._build_carousels([], pre_regroup_map)
        # With only 1 entity group that has 3 sources, it should create
        # hot first (highest hidden_count), and deep only if different group
        # Since there's only 1 entity group, hot takes it, deep has no candidates
        assert len(carousels) == 1
        assert carousels[0]["carousel_type"] == "hot"

    @pytest.mark.asyncio
    async def test_deep_carousel_from_second_entity_group(self):
        service = _setup_service()
        # Group 1: hot candidate (highest hidden_count)
        rep1 = MockContent(title="Trump article")
        hidden1 = [MockContent(title=f"Trump {i}") for i in range(5)]

        # Group 2: deep candidate (multi-source)
        rep2 = MockContent(title="Iran article")
        hidden2 = [MockContent(title=f"Iran {i}") for i in range(3)]

        all_articles = [rep1] + hidden1 + [rep2] + hidden2
        pre_regroup_map = {a.id: a for a in all_articles}

        service.entity_overflow = [
            _make_entity_group("trump", 5, rep1, hidden1, num_sources=2),
            _make_entity_group("iran", 3, rep2, hidden2, num_sources=3),
        ]
        service.keyword_overflow = []

        _, carousels = await service._build_carousels([], pre_regroup_map)
        types = [c["carousel_type"] for c in carousels]
        assert "hot" in types
        assert "deep" in types
        assert len(carousels) == 2


class TestBuildCarouselsBudgetAndRemoval:
    @pytest.mark.asyncio
    async def test_max_carousels_budget(self):
        service = _setup_service()
        articles = []
        entity_groups = []
        keyword_groups = []

        # Create many eligible groups
        for i in range(5):
            rep = MockContent(title=f"Entity {i}")
            hidden = [MockContent(title=f"Entity {i} art {j}") for j in range(3)]
            articles.extend([rep] + hidden)
            entity_groups.append(
                _make_entity_group(f"entity{i}", 3, rep, hidden, num_sources=3)
            )

        pre_regroup_map = {a.id: a for a in articles}
        service.entity_overflow = entity_groups
        service.keyword_overflow = keyword_groups

        _, carousels = await service._build_carousels(
            [], pre_regroup_map, max_carousels=3,
        )
        assert len(carousels) <= 3

    @pytest.mark.asyncio
    async def test_carousel_removes_from_feed(self):
        service = _setup_service()
        rep = MockContent(title="Trump main")
        hidden = [MockContent(title=f"Trump {i}") for i in range(3)]
        other = MockContent(title="Unrelated article")
        pre_regroup_map = {a.id: a for a in [rep] + hidden + [other]}

        service.entity_overflow = [
            _make_entity_group("trump", 3, rep, hidden)
        ]
        service.keyword_overflow = []

        result_feed = [rep, other]  # rep is in the feed
        result, carousels = await service._build_carousels(result_feed, pre_regroup_map)

        # rep should be removed from result (promoted to carousel)
        result_ids = {a.id for a in result}
        assert rep.id not in result_ids
        assert other.id in result_ids

    @pytest.mark.asyncio
    async def test_badges_count_matches_items(self):
        service = _setup_service()
        rep = MockContent(title="Article")
        hidden = [MockContent(title=f"Art {i}") for i in range(4)]
        pre_regroup_map = {a.id: a for a in [rep] + hidden}

        service.entity_overflow = [
            _make_entity_group("test", 4, rep, hidden)
        ]
        service.keyword_overflow = []

        _, carousels = await service._build_carousels([], pre_regroup_map)
        for c in carousels:
            assert len(c["badges"]) == len(c["items"])


class TestBuildCarouselsNoFilter:
    @pytest.mark.asyncio
    async def test_empty_overflow_produces_no_carousels(self):
        service = _setup_service()
        service.entity_overflow = []
        service.keyword_overflow = []

        result, carousels = await service._build_carousels([], {})
        assert carousels == []


# ================================================================
# Phase B tests (DB-driven carousels)
# ================================================================

# Named tuples to mimic DB row results
_SourceRow = namedtuple("_SourceRow", ["source_id", "name"])
_GemRow = namedtuple("_GemRow", ["id", "save_count"])


def _setup_service_with_no_overflow():
    """Service with empty overflow — isolates Phase B tests."""
    service = _setup_service()
    service.entity_overflow = []
    service.keyword_overflow = []
    return service


def _mock_scalars_result(items):
    """Create a mock that behaves like session.scalars() result."""
    mock_result = MagicMock()
    mock_result.all.return_value = items
    return mock_result


def _mock_execute_result(rows):
    """Create a mock that behaves like session.execute() result."""
    mock_result = MagicMock()
    mock_result.all.return_value = rows
    return mock_result


class TestBuildCarouselsNewSource:
    @pytest.mark.asyncio
    async def test_new_source_carousel_basic(self):
        service = _setup_service_with_no_overflow()
        user_id = uuid4()
        src_id = uuid4()

        # Mock: UserSource query returns 1 new source
        src_rows = [_SourceRow(source_id=src_id, name="TechCrunch")]
        # Mock: Content query returns 4 articles from that source
        articles = [
            MockContent(
                title=f"New article {i}",
                source=MockSource(name="TechCrunch", source_id=src_id),
            )
            for i in range(4)
        ]
        # Force source_id to match
        for a in articles:
            a.source_id = src_id

        execute_calls = 0

        async def mock_execute(stmt):
            nonlocal execute_calls
            execute_calls += 1
            if execute_calls == 1:
                return _mock_execute_result(src_rows)  # new_source
            return _mock_execute_result([])  # gems (empty)

        service.session.execute = AsyncMock(side_effect=mock_execute)
        service.session.scalars = AsyncMock(
            return_value=_mock_scalars_result(articles),
        )

        _, carousels = await service._build_carousels(
            [], {}, user_id=user_id,
        )

        new_src = [c for c in carousels if c["carousel_type"] == "new_source"]
        assert len(new_src) == 1
        c = new_src[0]
        assert "TechCrunch" in c["title"]
        assert c["position"] == 3
        assert c["badges"][0]["code"] == "new_source"
        assert len(c["items"]) == 4

    @pytest.mark.asyncio
    async def test_new_source_skipped_when_too_few_articles(self):
        service = _setup_service_with_no_overflow()
        user_id = uuid4()
        src_id = uuid4()

        src_rows = [_SourceRow(source_id=src_id, name="TechCrunch")]
        articles = [
            MockContent(
                title="Only one",
                source=MockSource(name="TechCrunch", source_id=src_id),
            )
        ]
        articles[0].source_id = src_id

        execute_calls = 0

        async def mock_execute(stmt):
            nonlocal execute_calls
            execute_calls += 1
            if execute_calls == 1:
                return _mock_execute_result(src_rows)  # new_source
            return _mock_execute_result([])  # gems (empty)

        service.session.execute = AsyncMock(side_effect=mock_execute)
        service.session.scalars = AsyncMock(
            return_value=_mock_scalars_result(articles),
        )

        _, carousels = await service._build_carousels(
            [], {}, user_id=user_id,
        )

        assert not any(c["carousel_type"] == "new_source" for c in carousels)

    @pytest.mark.asyncio
    async def test_new_source_skipped_when_no_new_sources(self):
        service = _setup_service_with_no_overflow()
        user_id = uuid4()

        # All queries return empty
        service.session.execute = AsyncMock(
            return_value=_mock_execute_result([]),
        )
        service.session.scalars = AsyncMock(
            return_value=_mock_scalars_result([]),
        )

        _, carousels = await service._build_carousels(
            [], {}, user_id=user_id,
        )

        assert not any(c["carousel_type"] == "new_source" for c in carousels)


class TestBuildCarouselsGems:
    @pytest.mark.asyncio
    async def test_gems_carousel_basic(self):
        service = _setup_service_with_no_overflow()
        user_id = uuid4()

        # Mock gems: 4 articles with 2+ saves
        gem_articles = [MockContent(title=f"Gem {i}") for i in range(4)]
        gem_rows = [
            _GemRow(id=a.id, save_count=5 - i) for i, a in enumerate(gem_articles)
        ]

        call_count = 0

        async def mock_execute(stmt):
            nonlocal call_count
            call_count += 1
            if call_count == 1:
                # First call: new_source query (no results)
                return _mock_execute_result([])
            # Second call: gems query
            return _mock_execute_result(gem_rows)

        service.session.execute = AsyncMock(side_effect=mock_execute)
        service.session.scalars = AsyncMock(
            return_value=_mock_scalars_result(gem_articles),
        )

        _, carousels = await service._build_carousels(
            [], {}, user_id=user_id,
        )

        gems = [c for c in carousels if c["carousel_type"] == "gems"]
        assert len(gems) == 1
        c = gems[0]
        assert c["title"] == "Pépites de la communauté"
        assert c["position"] == 15
        assert c["badges"][0]["code"] == "pepite"
        assert len(c["items"]) == 4

    @pytest.mark.asyncio
    async def test_gems_skipped_when_too_few_results(self):
        service = _setup_service_with_no_overflow()
        user_id = uuid4()

        # Only 2 gems (below MIN_CAROUSEL_ITEMS=3)
        gem_articles = [MockContent(title=f"Gem {i}") for i in range(2)]
        gem_rows = [
            _GemRow(id=a.id, save_count=1) for a in gem_articles
        ]

        call_count = 0

        async def mock_execute(stmt):
            nonlocal call_count
            call_count += 1
            if call_count == 1:
                return _mock_execute_result([])  # new_source
            return _mock_execute_result(gem_rows)  # gems

        service.session.execute = AsyncMock(side_effect=mock_execute)
        service.session.scalars = AsyncMock(
            return_value=_mock_scalars_result(gem_articles),
        )

        _, carousels = await service._build_carousels(
            [], {}, user_id=user_id,
        )

        assert not any(c["carousel_type"] == "gems" for c in carousels)


class TestBuildCarouselsSaved:
    @pytest.mark.asyncio
    async def test_saved_carousel_with_mixed_content_types(self):
        service = _setup_service_with_no_overflow()
        user_id = uuid4()

        saved_items = [
            MockContent(title="Saved article", content_type="article"),
            MockContent(title="Saved video", content_type="youtube"),
            MockContent(title="Saved podcast", content_type="podcast"),
        ]

        call_count = 0
        scalars_count = 0

        async def mock_execute(stmt):
            nonlocal call_count
            call_count += 1
            # new_source and gems queries return empty
            return _mock_execute_result([])

        async def mock_scalars(stmt):
            nonlocal scalars_count
            scalars_count += 1
            # saved query returns saved items
            return _mock_scalars_result(saved_items)

        service.session.execute = AsyncMock(side_effect=mock_execute)
        service.session.scalars = AsyncMock(side_effect=mock_scalars)

        _, carousels = await service._build_carousels(
            [], {}, user_id=user_id,
        )

        saved = [c for c in carousels if c["carousel_type"] == "saved"]
        assert len(saved) == 1
        c = saved[0]
        assert c["title"] == "Plus tard, c\u2019est maintenant !"
        assert c["position"] == 20
        assert len(c["items"]) == 3

        # Verify per-item badges
        assert c["badges"][0]["code"] == "saved_article"
        assert c["badges"][1]["code"] == "saved_video"
        assert c["badges"][2]["code"] == "saved_audio"

    @pytest.mark.asyncio
    async def test_saved_skipped_when_too_few(self):
        service = _setup_service_with_no_overflow()
        user_id = uuid4()

        saved_items = [MockContent(title="Only one saved")]

        async def mock_execute(stmt):
            return _mock_execute_result([])

        service.session.execute = AsyncMock(side_effect=mock_execute)
        service.session.scalars = AsyncMock(
            return_value=_mock_scalars_result(saved_items),
        )

        _, carousels = await service._build_carousels(
            [], {}, user_id=user_id,
        )

        assert not any(c["carousel_type"] == "saved" for c in carousels)


class TestBuildCarouselsPhaseB_Integration:
    @pytest.mark.asyncio
    async def test_no_phase_b_without_user_id(self):
        """Phase B carousels require user_id — without it, only Phase A runs."""
        service = _setup_service_with_no_overflow()

        _, carousels = await service._build_carousels([], {})
        assert carousels == []

    @pytest.mark.asyncio
    async def test_phase_b_respects_max_carousels(self):
        """Phase B carousels don't exceed max_carousels budget."""
        service = _setup_service_with_no_overflow()
        user_id = uuid4()

        # new_source returns enough articles
        src_id = uuid4()
        src_rows = [_SourceRow(source_id=src_id, name="Src")]
        articles = [MockContent(title=f"Art {i}") for i in range(5)]
        for a in articles:
            a.source_id = src_id

        service.session.execute = AsyncMock(
            return_value=_mock_execute_result(src_rows),
        )
        service.session.scalars = AsyncMock(
            return_value=_mock_scalars_result(articles),
        )

        # max_carousels=1 → only new_source should fit
        _, carousels = await service._build_carousels(
            [], {}, user_id=user_id, max_carousels=1,
        )
        assert len(carousels) == 1
        assert carousels[0]["carousel_type"] == "new_source"
