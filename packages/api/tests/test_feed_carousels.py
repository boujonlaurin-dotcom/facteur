"""Tests unitaires pour _build_carousels — promotion overflow → carrousels."""

import json
import pytest
from collections import namedtuple
from datetime import UTC, datetime, timedelta
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
        published_at=None,
    ):
        self.id = content_id or uuid4()
        self.title = title
        self.source = source or MockSource()
        self.source_id = self.source.id
        # One domain per source — feeds _extract_domain() in the topic
        # clustering used by the hot carousel (multi-source check).
        self.url = f"https://src-{self.source.id.hex[:8]}.example.com/{self.id.hex}"
        self.entities = entities or []
        self.content_type = content_type
        self.published_at = published_at or datetime.now(UTC)
        self.theme = None


def _make_story_articles(
    topic: str,
    n: int,
    entity: str | None = None,
    published_at=None,
):
    """N articles covering the same story (titles that Jaccard-cluster).

    Digits are stripped by normalize_title, so the trailing index keeps the
    token set identical across articles. Each article gets its own source
    (distinct domain) so the cluster passes the multi-source check.
    """
    articles = [
        MockContent(
            title=f"{topic} {i}",
            source=MockSource(name=f"Source {topic} {i}"),
            published_at=published_at,
        )
        for i in range(n)
    ]
    if entity:
        entity_json = json.dumps({"name": entity, "type": "PERSON"})
        for a in articles:
            a.entities = [entity_json]
    return articles


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
    async def test_hot_carousel_from_topic_cluster(self):
        service = _setup_service()
        story = _make_story_articles(
            "Trump annonce des sanctions douanières contre la Chine",
            5,
            entity="Trump",
        )
        pre_regroup_map = {a.id: a for a in story}

        service.entity_overflow = []
        service.keyword_overflow = []

        result_feed = [MockContent(title="Un sujet sans aucun rapport ici")]
        result, carousels = await service._build_carousels(result_feed, pre_regroup_map)

        assert len(carousels) == 1
        c = carousels[0]
        assert c["carousel_type"] == "hot"
        assert "Trump" in c["title"]
        assert c["emoji"] == "\U0001f50d"
        # Hot base position is 29 (cadence GNews ~6, business order)
        assert c["position"] == 29
        assert len(c["items"]) == 5
        assert len(c["badges"]) == len(c["items"])
        assert c["badges"][0]["code"] == "actu_chaude"

    @pytest.mark.asyncio
    async def test_hot_carousel_works_with_3_articles(self):
        """Min 3 clustered articles → should create carousel."""
        service = _setup_service()
        story = _make_story_articles(
            "Grève des contrôleurs aériens dans toute la France", 3
        )
        pre_regroup_map = {a.id: a for a in story}

        service.entity_overflow = []
        service.keyword_overflow = []

        result, carousels = await service._build_carousels([], pre_regroup_map)
        assert len(carousels) == 1
        assert len(carousels[0]["items"]) == 3

    @pytest.mark.asyncio
    async def test_hot_carousel_requires_min_3_articles(self):
        """2 clustered articles < MIN_CAROUSEL_ITEMS(3) → no carousel."""
        service = _setup_service()
        story = _make_story_articles(
            "Grève des contrôleurs aériens dans toute la France", 2
        )
        pre_regroup_map = {a.id: a for a in story}

        service.entity_overflow = []
        service.keyword_overflow = []

        result, carousels = await service._build_carousels([], pre_regroup_map)
        assert len(carousels) == 0

    @pytest.mark.asyncio
    async def test_hot_carousel_requires_multi_source(self):
        """A single source covering one story 4 times is not hot news."""
        service = _setup_service()
        source = MockSource(name="Mono Source")
        story = [
            MockContent(
                title=f"Grève des contrôleurs aériens dans toute la France {i}",
                source=source,
            )
            for i in range(4)
        ]
        pre_regroup_map = {a.id: a for a in story}

        service.entity_overflow = []
        service.keyword_overflow = []

        _, carousels = await service._build_carousels([], pre_regroup_map)
        assert carousels == []

    @pytest.mark.asyncio
    async def test_hot_title_without_dominant_entity(self):
        """No entity shared by >= 2 articles → plain 'Actu chaude' title."""
        service = _setup_service()
        story = _make_story_articles(
            "Grève des contrôleurs aériens dans toute la France", 3
        )
        pre_regroup_map = {a.id: a for a in story}

        service.entity_overflow = []
        service.keyword_overflow = []

        _, carousels = await service._build_carousels([], pre_regroup_map)
        assert len(carousels) == 1
        assert carousels[0]["title"] == "Actu chaude"


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
    async def test_only_hot_from_single_cluster(self):
        service = _setup_service()
        story = _make_story_articles(
            "Téhéran reprend les négociations sur le nucléaire iranien", 4
        )
        pre_regroup_map = {a.id: a for a in story}

        service.entity_overflow = []
        service.keyword_overflow = []

        _, carousels = await service._build_carousels([], pre_regroup_map)
        assert len(carousels) == 1
        assert carousels[0]["carousel_type"] == "hot"

    @pytest.mark.asyncio
    async def test_only_one_hot_even_with_two_clusters(self):
        """With user_id=None, only hot carousel is created (deep is disabled,
        and would require user_id anyway)."""
        service = _setup_service()
        story1 = _make_story_articles(
            "Trump annonce des sanctions douanières contre la Chine", 6
        )
        story2 = _make_story_articles(
            "Téhéran reprend les négociations sur le nucléaire iranien", 4
        )
        pre_regroup_map = {a.id: a for a in story1 + story2}

        service.entity_overflow = []
        service.keyword_overflow = []

        _, carousels = await service._build_carousels([], pre_regroup_map)
        types = [c["carousel_type"] for c in carousels]
        assert "hot" in types
        # deep requires user_id + find_perspectives_for_read_article (DB-driven)
        assert len(carousels) == 1


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
        story = _make_story_articles(
            "Trump annonce des sanctions douanières contre la Chine", 4
        )
        promoted = story[0]
        other = MockContent(title="Un sujet sans aucun rapport ici")
        pre_regroup_map = {a.id: a for a in story + [other]}

        service.entity_overflow = []
        service.keyword_overflow = []

        result_feed = [promoted, other]  # promoted is in the feed
        result, carousels = await service._build_carousels(result_feed, pre_regroup_map)

        # promoted should be removed from result (promoted to carousel)
        assert len(carousels) == 1
        result_ids = {a.id for a in result}
        assert promoted.id not in result_ids
        assert other.id in result_ids

    @pytest.mark.asyncio
    async def test_badges_count_matches_items(self):
        service = _setup_service()
        story = _make_story_articles(
            "Trump annonce des sanctions douanières contre la Chine", 5
        )
        pre_regroup_map = {a.id: a for a in story}

        service.entity_overflow = []
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
_SourceRow = namedtuple("_SourceRow", ["source_id", "name", "added_at"])
_CommunityRow = namedtuple("_CommunityRow", ["id", "score", "sunflower_count"])


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
    """Create a mock that behaves like session.execute() result.

    Handles both .all() and .scalars().all() chains.
    """
    mock_result = MagicMock()
    mock_result.all.return_value = rows
    mock_scalars = MagicMock()
    mock_scalars.all.return_value = rows
    mock_result.scalars.return_value = mock_scalars
    return mock_result


class TestBuildCarouselsNewSource:
    @pytest.mark.asyncio
    async def test_new_source_carousel_basic(self):
        service = _setup_service_with_no_overflow()
        user_id = uuid4()
        src_id = uuid4()

        # Mock: UserSource query returns 1 new source (added 2 days ago → position 3)
        two_days_ago = datetime.now(UTC) - timedelta(days=2)
        src_rows = [_SourceRow(source_id=src_id, name="TechCrunch", added_at=two_days_ago)]
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
            # 1: consumed_ids → empty
            if execute_calls == 1:
                return _mock_execute_result([])
            if execute_calls == 2:
                return _mock_execute_result(src_rows)  # new_source
            return _mock_execute_result([])  # quiet_sources + community (empty)

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
        assert c["position"] >= 5  # MIN_CAROUSEL_POSITION enforced
        assert c["badges"][0]["code"] == "new_source"
        assert len(c["items"]) == 4

    @pytest.mark.asyncio
    async def test_new_source_skipped_when_too_few_articles(self):
        service = _setup_service_with_no_overflow()
        user_id = uuid4()
        src_id = uuid4()

        two_days_ago = datetime.now(UTC) - timedelta(days=2)
        src_rows = [_SourceRow(source_id=src_id, name="TechCrunch", added_at=two_days_ago)]
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
                return _mock_execute_result([])  # consumed_ids
            if execute_calls == 2:
                return _mock_execute_result(src_rows)  # new_source
            return _mock_execute_result([])  # quiet_sources + community

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
        async def mock_execute(stmt):
            return _mock_execute_result([])

        service.session.execute = AsyncMock(side_effect=mock_execute)
        service.session.scalars = AsyncMock(
            return_value=_mock_scalars_result([]),
        )

        _, carousels = await service._build_carousels(
            [], {}, user_id=user_id,
        )

        assert not any(c["carousel_type"] == "new_source" for c in carousels)


class TestBuildCarouselsCommunity:
    @pytest.mark.asyncio
    async def test_community_carousel_basic(self):
        service = _setup_service_with_no_overflow()
        user_id = uuid4()

        # Mock community: 4 🌻 articles with decay scores and sunflower counts
        community_articles = [MockContent(title=f"Community {i}") for i in range(4)]
        community_rows = [
            _CommunityRow(id=a.id, score=5.0 - i, sunflower_count=5 - i)
            for i, a in enumerate(community_articles)
        ]

        call_count = 0

        async def mock_execute(stmt):
            nonlocal call_count
            call_count += 1
            # 1: consumed_ids, 2: new_source, 3: quiet_sources → empty
            if call_count <= 3:
                return _mock_execute_result([])
            # 4: community query
            return _mock_execute_result(community_rows)

        service.session.execute = AsyncMock(side_effect=mock_execute)
        service.session.scalars = AsyncMock(
            return_value=_mock_scalars_result(community_articles),
        )

        _, carousels = await service._build_carousels(
            [], {}, user_id=user_id,
        )

        community = [c for c in carousels if c["carousel_type"] == "community"]
        assert len(community) == 1
        c = community[0]
        assert c["title"] == "Recos de la communauté"
        assert c["position"] >= 5  # MIN_CAROUSEL_POSITION enforced; slot shuffled
        assert c["badges"][0]["code"] == "community"
        assert len(c["items"]) == 4

    @pytest.mark.asyncio
    async def test_community_skipped_when_too_few_results(self):
        service = _setup_service_with_no_overflow()
        user_id = uuid4()

        # Only 2 community items (below MIN_CAROUSEL_ITEMS=3)
        community_articles = [MockContent(title=f"Community {i}") for i in range(2)]
        community_rows = [
            _CommunityRow(id=a.id, score=1.0, sunflower_count=1)
            for a in community_articles
        ]

        call_count = 0

        async def mock_execute(stmt):
            nonlocal call_count
            call_count += 1
            # 1: consumed_ids, 2: new_source, 3: quiet_sources → empty
            if call_count <= 3:
                return _mock_execute_result([])
            # 4: community
            return _mock_execute_result(community_rows)

        service.session.execute = AsyncMock(side_effect=mock_execute)
        service.session.scalars = AsyncMock(
            return_value=_mock_scalars_result(community_articles),
        )

        _, carousels = await service._build_carousels(
            [], {}, user_id=user_id,
        )

        assert not any(c["carousel_type"] == "community" for c in carousels)


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

        # All execute calls return empty (consumed_ids, new_source, quiet_sources, community)
        async def mock_execute(stmt):
            return _mock_execute_result([])

        service.session.execute = AsyncMock(side_effect=mock_execute)
        service.session.scalars = AsyncMock(
            return_value=_mock_scalars_result(saved_items),
        )

        _, carousels = await service._build_carousels(
            [], {}, user_id=user_id,
        )

        saved = [c for c in carousels if c["carousel_type"] == "saved"]
        assert len(saved) == 1
        c = saved[0]
        assert c["title"] == "Plus tard, c\u2019est maintenant !"
        assert c["position"] >= 5  # MIN_CAROUSEL_POSITION enforced; slot shuffled
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
        two_days_ago = datetime.now(UTC) - timedelta(days=2)
        src_rows = [_SourceRow(source_id=src_id, name="Src", added_at=two_days_ago)]
        articles = [MockContent(title=f"Art {i}") for i in range(5)]
        for a in articles:
            a.source_id = src_id

        execute_calls = 0

        async def mock_execute(stmt):
            nonlocal execute_calls
            execute_calls += 1
            # 1: consumed_ids → empty
            if execute_calls == 1:
                return _mock_execute_result([])
            if execute_calls == 2:
                return _mock_execute_result(src_rows)  # new_source
            return _mock_execute_result([])  # quiet_sources + community

        service.session.execute = AsyncMock(side_effect=mock_execute)
        service.session.scalars = AsyncMock(
            return_value=_mock_scalars_result(articles),
        )

        # max_carousels=1 → only new_source should fit
        _, carousels = await service._build_carousels(
            [], {}, user_id=user_id, max_carousels=1,
        )
        assert len(carousels) == 1
        assert carousels[0]["carousel_type"] == "new_source"


# ================================================================
# Engagement: position plancher, daily shuffle, probabilistic content
# ================================================================


class TestMinCarouselPosition:
    @pytest.mark.asyncio
    async def test_no_carousel_below_min_position(self):
        """All carousels must have position >= MIN_CAROUSEL_POSITION (4)."""
        service = _setup_service()
        story = _make_story_articles(
            "Trump annonce des sanctions douanières contre la Chine", 5
        )
        pre_regroup_map = {a.id: a for a in story}

        service.entity_overflow = []
        service.keyword_overflow = []

        _, carousels = await service._build_carousels([], pre_regroup_map)
        for c in carousels:
            assert c["position"] >= 4, (
                f"Carousel {c['carousel_type']} at position {c['position']} < 4"
            )

    @pytest.mark.asyncio
    async def test_hot_position_unchanged_without_user_id(self):
        """Without user_id, hot carousel falls back to its business-order base."""
        service = _setup_service()
        story = _make_story_articles(
            "Trump annonce des sanctions douanières contre la Chine", 5
        )
        pre_regroup_map = {a.id: a for a in story}

        service.entity_overflow = []
        service.keyword_overflow = []

        _, carousels = await service._build_carousels([], pre_regroup_map)
        assert len(carousels) == 1
        # Hot base position is 29 (no jitter without user_id)
        assert carousels[0]["position"] == 29


def _setup_service_with_overflow_and_mocks():
    """Service with entity overflow + mocked session for Phase B queries."""
    service = _setup_service()
    # Mock session for consumed_ids + Phase B queries (all return empty)
    service.session.execute = AsyncMock(return_value=_mock_execute_result([]))
    service.session.scalars = AsyncMock(return_value=_mock_scalars_result([]))
    return service


class TestDailyJitter:
    """Story 12.8: deterministic daily jitter around business-order base."""

    @pytest.mark.asyncio
    async def test_jitter_deterministic_same_day(self):
        """Same user_id + same day → same positions on repeated calls."""
        service = _setup_service_with_overflow_and_mocks()
        user_id = uuid4()
        story = _make_story_articles(
            "Trump annonce des sanctions douanières contre la Chine", 5
        )
        pre_regroup_map = {a.id: a for a in story}

        service.entity_overflow = []
        service.keyword_overflow = []

        _, carousels1 = await service._build_carousels(
            [], pre_regroup_map, user_id=user_id,
        )
        _, carousels2 = await service._build_carousels(
            [], pre_regroup_map, user_id=user_id,
        )

        pos1 = [c["position"] for c in carousels1]
        pos2 = [c["position"] for c in carousels2]
        assert pos1 == pos2

    @pytest.mark.asyncio
    async def test_jitter_varies_across_users(self):
        """Different user_ids on the same day may get different positions."""
        service = _setup_service_with_overflow_and_mocks()
        story = _make_story_articles(
            "Trump annonce des sanctions douanières contre la Chine", 5
        )
        pre_regroup_map = {a.id: a for a in story}

        service.entity_overflow = []
        service.keyword_overflow = []

        positions = set()
        for _ in range(20):
            _, carousels = await service._build_carousels(
                [], pre_regroup_map, user_id=uuid4(),
            )
            if carousels:
                positions.add(carousels[0]["position"])

        assert len(positions) > 1, "Positions should vary across different users"

    @pytest.mark.asyncio
    async def test_jitter_stays_within_base_plus_minus_2(self):
        """Jittered positions stay within base ±2 of the business-order slot."""
        from app.services.recommendation_service import RecommendationService

        service = _setup_service_with_overflow_and_mocks()
        story = _make_story_articles(
            "Trump annonce des sanctions douanières contre la Chine", 5
        )
        pre_regroup_map = {a.id: a for a in story}

        service.entity_overflow = []
        service.keyword_overflow = []

        base_hot = RecommendationService._CAROUSEL_BASE_POSITIONS["hot"]
        MIN_POS = 5
        for _ in range(20):
            _, carousels = await service._build_carousels(
                [], pre_regroup_map, user_id=uuid4(),
            )
            for c in carousels:
                pos = c["position"]
                # Only one carousel here → no collisions. Jitter is ±2 around
                # the base, clamped to MIN_CAROUSEL_POSITION.
                assert max(MIN_POS, base_hot - 2) <= pos <= base_hot + 2, (
                    f"Hot position {pos} outside jitter band for base {base_hot}"
                )


class TestProbabilisticHotCluster:
    def test_selects_among_top_clusters(self):
        """With multiple eligible clusters, different seeds may select different ones."""
        from app.services.article_clustering_service import find_hot_cluster

        now = datetime.now(UTC)
        # 3 clusters of size 5, 4, 3
        all_articles = (
            _make_story_articles(
                "Trump annonce des sanctions douanières contre la Chine",
                5,
                published_at=now,
            )
            + _make_story_articles(
                "Téhéran reprend les négociations sur le nucléaire iranien",
                4,
                published_at=now,
            )
            + _make_story_articles(
                "Une intelligence artificielle remporte un concours de mathématiques",
                3,
                published_at=now,
            )
        )

        # Run with many seeds — should sometimes select non-trump clusters
        selected_keys = set()
        for seed in range(100):
            cluster_key, _, articles = find_hot_cluster(
                all_articles, seed=seed,
            )
            if cluster_key:
                selected_keys.add(cluster_key)

        # With weighted random among 3 clusters, we expect at least 2 different selections
        assert len(selected_keys) >= 2, (
            f"Expected variety in cluster selection, got only: {selected_keys}"
        )

    def test_deterministic_with_same_seed(self):
        """Same seed always selects the same cluster."""
        from app.services.article_clustering_service import find_hot_cluster

        now = datetime.now(UTC)
        all_articles = _make_story_articles(
            "Trump annonce des sanctions douanières contre la Chine",
            4,
            published_at=now,
        ) + _make_story_articles(
            "Téhéran reprend les négociations sur le nucléaire iranien",
            3,
            published_at=now,
        )

        key1, _, _ = find_hot_cluster(all_articles, seed=42)
        key2, _, _ = find_hot_cluster(all_articles, seed=42)
        assert key1 == key2

    def test_unrelated_articles_sharing_entity_do_not_cluster(self):
        """Passing mentions of the same entity must not form a hot cluster
        (the old NER-entity grouping regression: 'Actu chaude : Trump' with
        unrelated articles)."""
        from app.services.article_clustering_service import find_hot_cluster

        now = datetime.now(UTC)
        entity_json = json.dumps({"name": "Trump", "type": "PERSON"})
        titles = [
            "La réforme des retraites suspendue par le gouvernement français",
            "Le Vendée Globe bat son record absolu de participation cette année",
            "Une éruption volcanique majeure paralyse le trafic aérien en Islande",
        ]
        articles = [MockContent(title=t, published_at=now) for t in titles]
        for a in articles:
            a.entities = [entity_json]

        cluster_key, display_name, result = find_hot_cluster(articles)
        assert result == []
        assert cluster_key is None
