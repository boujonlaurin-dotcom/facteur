"""Tests E2E pour Epic 11 — Custom Topics.

Couvre:
1. Modèle UserTopicProfile (CRUD DB)
2. TopicEnrichmentService (LLM mock)
3. UserCustomTopicLayer (scoring boost)
4. Clustering (regroupement articles)
5. Suggestions (top consumed topics)
"""

import json
from datetime import datetime, timedelta
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest
import pytest_asyncio
from sqlalchemy import select

from app.models.content import Content, UserContentStatus
from app.models.enums import ContentStatus, ContentType, SourceType
from app.models.source import Source
from app.models.user import UserProfile
from app.models.user_topic_profile import UserTopicProfile
from app.services.ml.topic_enrichment_service import TopicEnrichmentService
from app.services.recommendation.layers.user_custom_topics import UserCustomTopicLayer
from app.services.recommendation.scoring_config import ScoringWeights
from app.services.recommendation.scoring_engine import ScoringContext
from app.services.recommendation_service import RecommendationService

# ============================================================
# Fixtures
# ============================================================


@pytest_asyncio.fixture
async def test_user(db_session):
    """Create a test user profile."""
    user_id = uuid4()
    profile = UserProfile(
        user_id=user_id,
        display_name="Test User",
        onboarding_completed=True,
    )
    db_session.add(profile)
    await db_session.commit()
    return profile


@pytest_asyncio.fixture
async def test_source_curated(db_session):
    """Create a curated test source."""
    source = Source(
        id=uuid4(),
        name="Tech Daily",
        url="https://techdaily.example.com",
        feed_url=f"https://techdaily.example.com/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="tech",
        is_active=True,
        is_curated=True,
    )
    db_session.add(source)
    await db_session.commit()
    return source


# ============================================================
# 1. UserTopicProfile Model Tests (DB CRUD)
# ============================================================


class TestUserTopicProfileModel:
    @pytest.mark.asyncio
    async def test_create_topic_profile(self, db_session, test_user):
        """Test creating a UserTopicProfile in the database."""
        topic = UserTopicProfile(
            user_id=test_user.user_id,
            topic_name="Intelligence Artificielle",
            slug_parent="ai",
            keywords=["GPT", "LLM", "OpenAI", "machine learning"],
            intent_description="Suivi des actualités IA",
            source_type="explicit",
            priority_multiplier=1.0,
            composite_score=0.0,
        )
        db_session.add(topic)
        await db_session.commit()

        # Fetch it back
        result = await db_session.scalar(
            select(UserTopicProfile).where(
                UserTopicProfile.user_id == test_user.user_id
            )
        )
        assert result is not None
        assert result.topic_name == "Intelligence Artificielle"
        assert result.slug_parent == "ai"
        assert "GPT" in result.keywords
        assert result.priority_multiplier == 1.0

    @pytest.mark.asyncio
    async def test_unique_constraint_user_slug(self, db_session, test_user):
        """Test that (user_id, slug_parent) UniqueConstraint works."""
        topic1 = UserTopicProfile(
            user_id=test_user.user_id,
            topic_name="IA",
            slug_parent="ai",
            keywords=["GPT"],
        )
        db_session.add(topic1)
        await db_session.commit()

        topic2 = UserTopicProfile(
            user_id=test_user.user_id,
            topic_name="Machine Learning",
            slug_parent="ai",  # Same slug_parent
            keywords=["ML"],
        )
        db_session.add(topic2)
        with pytest.raises(Exception):  # noqa: B017 IntegrityError
            await db_session.commit()

    @pytest.mark.asyncio
    async def test_update_priority_multiplier(self, db_session, test_user):
        """Test updating the priority multiplier."""
        topic = UserTopicProfile(
            user_id=test_user.user_id,
            topic_name="Climat",
            slug_parent="climate",
            keywords=["réchauffement"],
        )
        db_session.add(topic)
        await db_session.commit()

        # Update
        topic.priority_multiplier = 2.0
        await db_session.commit()

        result = await db_session.scalar(
            select(UserTopicProfile).where(UserTopicProfile.id == topic.id)
        )
        assert result.priority_multiplier == 2.0

    @pytest.mark.asyncio
    async def test_delete_topic(self, db_session, test_user):
        """Test deleting a topic."""
        topic = UserTopicProfile(
            user_id=test_user.user_id,
            topic_name="Crypto",
            slug_parent="finance",
            keywords=["bitcoin"],
        )
        db_session.add(topic)
        await db_session.commit()

        topic_id = topic.id
        await db_session.delete(topic)
        await db_session.commit()

        result = await db_session.scalar(
            select(UserTopicProfile).where(UserTopicProfile.id == topic_id)
        )
        assert result is None

    @pytest.mark.asyncio
    async def test_cascade_delete_on_user(self, db_session):
        """Test that topics are deleted when user profile is deleted."""
        user_id = uuid4()
        profile = UserProfile(user_id=user_id, display_name="Deletable")
        db_session.add(profile)
        await db_session.commit()

        topic = UserTopicProfile(
            user_id=user_id,
            topic_name="Test",
            slug_parent="tech",
            keywords=[],
        )
        db_session.add(topic)
        await db_session.commit()
        topic_id = topic.id

        # Delete user profile
        await db_session.delete(profile)
        await db_session.commit()

        result = await db_session.scalar(
            select(UserTopicProfile).where(UserTopicProfile.id == topic_id)
        )
        assert result is None


# ============================================================
# 2. TopicEnrichmentService Tests (LLM Mock)
# ============================================================


class TestTopicEnrichmentService:
    @pytest.mark.asyncio
    async def test_enrich_via_llm_success(self):
        """Test successful LLM enrichment with mocked Mistral API."""
        service = TopicEnrichmentService()
        service._ready = True

        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.raise_for_status = MagicMock()
        mock_response.json.return_value = {
            "choices": [
                {
                    "message": {
                        "content": json.dumps(
                            {
                                "slug_parent": "climate",
                                "keywords": [
                                    "véhicule électrique",
                                    "Tesla",
                                    "batterie",
                                    "recharge",
                                    "mobilité durable",
                                ],
                                "intent_description": "Suivi des actualités sur les voitures électriques",
                            }
                        )
                    }
                }
            ]
        }

        mock_client = AsyncMock()
        mock_client.post = AsyncMock(return_value=mock_response)
        service._client = mock_client

        result = await service.enrich("Voiture électrique")

        assert result.slug_parent == "climate"
        assert len(result.keywords) >= 3
        assert "Tesla" in result.keywords
        assert "Suivi" in result.intent_description

    @pytest.mark.asyncio
    async def test_enrich_via_llm_invalid_slug_falls_back(self):
        """Test that an invalid slug from LLM triggers fallback."""
        service = TopicEnrichmentService()
        service._ready = True

        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.raise_for_status = MagicMock()
        mock_response.json.return_value = {
            "choices": [
                {
                    "message": {
                        "content": json.dumps(
                            {
                                "slug_parent": "invalid_slug_xyz",
                                "keywords": ["test"],
                                "intent_description": "test",
                            }
                        )
                    }
                }
            ]
        }

        mock_client = AsyncMock()
        mock_client.post = AsyncMock(return_value=mock_response)
        service._client = mock_client

        # Should fall back to fuzzy matching
        result = await service.enrich("Intelligence artificielle")
        assert result.slug_parent in {
            "ai",
            "tech",
        }  # Fuzzy match should find "ai" or "tech"

    @pytest.mark.asyncio
    async def test_enrich_fallback_no_api_key(self):
        """Test fallback when no API key is set."""
        service = TopicEnrichmentService()
        service._ready = False

        result = await service.enrich("Intelligence artificielle")
        assert result.slug_parent == "ai"  # Fuzzy match on SLUG_TO_LABEL
        assert len(result.keywords) >= 1

    @pytest.mark.asyncio
    async def test_enrich_empty_name_raises(self):
        """Test that empty topic name raises ValueError."""
        service = TopicEnrichmentService()
        with pytest.raises(ValueError, match="empty"):
            await service.enrich("")

    def test_fallback_exact_slug_match(self):
        """Test fallback with an exact slug match."""
        service = TopicEnrichmentService()
        result = service._fallback_enrich("cybersecurity")
        assert result.slug_parent == "cybersecurity"

    def test_fallback_label_match(self):
        """Test fallback matching on French labels."""
        service = TopicEnrichmentService()
        result = service._fallback_enrich("Économie")
        assert result.slug_parent == "economy"


# ============================================================
# 3. UserCustomTopicLayer Tests (Scoring Boost)
# ============================================================


class TestUserCustomTopicLayer:
    @pytest.fixture
    def mock_now(self):
        return datetime.utcnow()

    @pytest.fixture
    def ai_topic(self):
        """Create a mock UserTopicProfile for AI."""
        topic = MagicMock()
        topic.slug_parent = "ai"
        topic.keywords = ["GPT", "LLM", "machine learning"]
        topic.topic_name = "Intelligence Artificielle"
        topic.priority_multiplier = 1.0
        return topic

    @pytest.fixture
    def base_context_with_topic(self, mock_now, ai_topic):
        return ScoringContext(
            user_profile=None,
            user_interests={"tech"},
            user_interest_weights={"tech": 1.0},
            followed_source_ids=set(),
            user_prefs={},
            now=mock_now,
            user_custom_topics=[ai_topic],
        )

    def test_slug_match_scores(self, base_context_with_topic):
        """Test that an article with matching slug_parent gets a boost."""
        source = Source(id=uuid4(), name="TechSource", theme="tech")
        content = Content(
            id=uuid4(),
            title="New AI Model Released",
            url="http://example.com/ai",
            source_id=source.id,
            source=source,
            published_at=datetime.utcnow(),
            content_type=ContentType.ARTICLE,
            topics=["ai", "tech"],
        )

        layer = UserCustomTopicLayer()
        score = layer.score(content, base_context_with_topic)

        expected = ScoringWeights.CUSTOM_TOPIC_BASE_BONUS * 1.0
        assert score == expected

    def test_keyword_match_in_title(self, mock_now, ai_topic):
        """Test that a keyword match in title triggers boost."""
        context = ScoringContext(
            user_profile=None,
            user_interests=set(),
            user_interest_weights={},
            followed_source_ids=set(),
            user_prefs={},
            now=mock_now,
            user_custom_topics=[ai_topic],
        )

        source = Source(id=uuid4(), name="GeneralSource", theme="society")
        content = Content(
            id=uuid4(),
            title="GPT-5 annoncé par OpenAI",
            url="http://example.com/gpt5",
            source_id=source.id,
            source=source,
            published_at=datetime.utcnow(),
            content_type=ContentType.ARTICLE,
            topics=["tech"],  # No "ai" in topics
        )

        layer = UserCustomTopicLayer()
        score = layer.score(content, context)

        assert score == ScoringWeights.CUSTOM_TOPIC_BASE_BONUS * 1.0

    def test_priority_multiplier_affects_score(self, mock_now):
        """Test that priority_multiplier scales the boost correctly."""
        layer = UserCustomTopicLayer()
        source = Source(id=uuid4(), name="TechSource", theme="tech")
        content = Content(
            id=uuid4(),
            title="AI Article",
            url="http://example.com",
            source_id=source.id,
            source=source,
            published_at=datetime.utcnow(),
            content_type=ContentType.ARTICLE,
            topics=["ai"],
        )

        # Test with multiplier 0.5
        topic_low = MagicMock()
        topic_low.slug_parent = "ai"
        topic_low.keywords = []
        topic_low.topic_name = "IA"
        topic_low.priority_multiplier = 0.5

        ctx_low = ScoringContext(
            user_profile=None,
            user_interests=set(),
            user_interest_weights={},
            followed_source_ids=set(),
            user_prefs={},
            now=mock_now,
            user_custom_topics=[topic_low],
        )
        score_low = layer.score(content, ctx_low)

        # Test with multiplier 2.0
        topic_high = MagicMock()
        topic_high.slug_parent = "ai"
        topic_high.keywords = []
        topic_high.topic_name = "IA"
        topic_high.priority_multiplier = 2.0

        ctx_high = ScoringContext(
            user_profile=None,
            user_interests=set(),
            user_interest_weights={},
            followed_source_ids=set(),
            user_prefs={},
            now=mock_now,
            user_custom_topics=[topic_high],
        )
        score_high = layer.score(content, ctx_high)

        assert score_high == score_low * 4.0  # 2.0/0.5 = 4x
        assert score_high == ScoringWeights.CUSTOM_TOPIC_BASE_BONUS * 2.0
        assert score_low == ScoringWeights.CUSTOM_TOPIC_BASE_BONUS * 0.5

    def test_no_match_returns_zero(self, mock_now):
        """Test that articles not matching any custom topic get 0."""
        topic = MagicMock()
        topic.slug_parent = "ai"
        topic.keywords = ["GPT"]
        topic.topic_name = "IA"
        topic.priority_multiplier = 1.0

        context = ScoringContext(
            user_profile=None,
            user_interests=set(),
            user_interest_weights={},
            followed_source_ids=set(),
            user_prefs={},
            now=mock_now,
            user_custom_topics=[topic],
        )

        source = Source(id=uuid4(), name="SportSource", theme="sport")
        content = Content(
            id=uuid4(),
            title="Match de foot ce soir",
            url="http://example.com/foot",
            source_id=source.id,
            source=source,
            published_at=datetime.utcnow(),
            content_type=ContentType.ARTICLE,
            topics=["sport"],
        )

        layer = UserCustomTopicLayer()
        score = layer.score(content, context)
        assert score == 0.0

    def test_no_custom_topics_returns_zero(self, mock_now):
        """Test that no custom topics means zero score."""
        context = ScoringContext(
            user_profile=None,
            user_interests=set(),
            user_interest_weights={},
            followed_source_ids=set(),
            user_prefs={},
            now=mock_now,
            user_custom_topics=[],
        )

        source = Source(id=uuid4(), name="Source", theme="tech")
        content = Content(
            id=uuid4(),
            title="AI Article",
            url="http://example.com",
            source_id=source.id,
            source=source,
            published_at=datetime.utcnow(),
            content_type=ContentType.ARTICLE,
            topics=["ai"],
        )

        layer = UserCustomTopicLayer()
        score = layer.score(content, context)
        assert score == 0.0


# ============================================================
# 4. Clustering Tests
# ============================================================


class TestClustering:
    def _make_content(self, topics, title="Article", score_hint=0):
        """Helper to create a Content object for clustering tests."""
        source = Source(id=uuid4(), name="Src", theme="tech")
        return Content(
            id=uuid4(),
            title=f"{title} {score_hint}",
            url=f"http://example.com/{uuid4()}",
            source_id=source.id,
            source=source,
            published_at=datetime.utcnow() - timedelta(hours=score_hint),
            content_type=ContentType.ARTICLE,
            topics=topics,
        )

    def _make_topic(self, slug, name="Topic"):
        topic = MagicMock()
        topic.slug_parent = slug
        topic.topic_name = name
        return topic

    def test_cluster_with_enough_articles(self):
        """Test clustering with >=3 articles on same topic."""
        articles = [self._make_content(["ai"], f"AI Article {i}", i) for i in range(5)]
        topics = [self._make_topic("ai", "Intelligence Artificielle")]

        filtered, clusters = RecommendationService.build_clusters(
            articles, topics, min_articles=3
        )

        assert len(clusters) == 1
        assert clusters[0]["topic_slug"] == "ai"
        assert clusters[0]["hidden_count"] == 4
        assert len(clusters[0]["hidden_ids"]) == 4
        # First article (best scored) should be the representative
        assert clusters[0]["representative_id"] == articles[0].id
        # Filtered list should only have the representative
        assert len(filtered) == 1
        assert filtered[0].id == articles[0].id

    def test_no_cluster_below_threshold(self):
        """Test that <3 articles don't form a cluster."""
        articles = [self._make_content(["ai"], f"AI Article {i}", i) for i in range(2)]
        topics = [self._make_topic("ai", "IA")]

        filtered, clusters = RecommendationService.build_clusters(
            articles, topics, min_articles=3
        )

        assert len(clusters) == 0
        assert len(filtered) == 2  # All articles remain

    def test_max_clusters_limit(self):
        """Test that max_clusters limits the number of clusters."""
        articles = (
            [self._make_content(["ai"], f"AI {i}", i) for i in range(4)]
            + [self._make_content(["climate"], f"Climate {i}", i) for i in range(4)]
            + [self._make_content(["finance"], f"Finance {i}", i) for i in range(4)]
            + [self._make_content(["sport"], f"Sport {i}", i) for i in range(4)]
        )
        topics = [
            self._make_topic("ai", "IA"),
            self._make_topic("climate", "Climat"),
            self._make_topic("finance", "Finance"),
            self._make_topic("sport", "Sport"),
        ]

        filtered, clusters = RecommendationService.build_clusters(
            articles, topics, min_articles=3, max_clusters=3
        )

        assert len(clusters) == 3  # Max 3 clusters

    def test_no_topics_no_clusters(self):
        """Test that no custom topics means no clusters."""
        articles = [self._make_content(["ai"], "AI", 0)]

        filtered, clusters = RecommendationService.build_clusters(articles, [])

        assert len(clusters) == 0
        assert len(filtered) == 1

    def test_mixed_articles_only_cluster_matching(self):
        """Test that non-matching articles stay in feed, only matching ones cluster."""
        ai_articles = [self._make_content(["ai"], f"AI {i}", i) for i in range(4)]
        sport_articles = [
            self._make_content(["sport"], f"Sport {i}", i) for i in range(2)
        ]
        all_articles = ai_articles + sport_articles

        topics = [self._make_topic("ai", "IA")]

        filtered, clusters = RecommendationService.build_clusters(
            all_articles, topics, min_articles=3
        )

        assert len(clusters) == 1
        # Filtered should have: 1 AI representative + 2 sport articles
        assert len(filtered) == 3


# ============================================================
# 5. Recency Base Adjustment Test
# ============================================================


class TestRecencyBaseAdjustment:
    def test_recency_base_is_100(self):
        """Verify recency_base has been raised to 100 (Epic 11)."""
        assert ScoringWeights.recency_base == 100.0

    def test_custom_topic_base_bonus_is_15(self):
        """Verify CUSTOM_TOPIC_BASE_BONUS is set."""
        assert ScoringWeights.CUSTOM_TOPIC_BASE_BONUS == 15.0


# ============================================================
# 6. Integration: Scoring with Custom Topic in Full Engine
# ============================================================


class TestScoringIntegration:
    def test_custom_topic_boosts_article_in_full_engine(self):
        """Test that an article matching a custom topic scores higher
        than an identical article without the topic match, when using
        the full ScoringEngine pipeline."""
        from app.services.recommendation.scoring_engine import ScoringEngine

        engine = ScoringEngine([UserCustomTopicLayer()])

        topic = MagicMock()
        topic.slug_parent = "ai"
        topic.keywords = ["GPT"]
        topic.topic_name = "IA"
        topic.priority_multiplier = 2.0

        now = datetime.utcnow()
        source = Source(id=uuid4(), name="Src", theme="tech")

        # Article matching the topic
        article_match = Content(
            id=uuid4(),
            title="GPT-5 is here",
            url="http://example.com/1",
            source_id=source.id,
            source=source,
            published_at=now,
            content_type=ContentType.ARTICLE,
            topics=["ai", "tech"],
        )

        # Article NOT matching the topic
        article_no_match = Content(
            id=uuid4(),
            title="Football results",
            url="http://example.com/2",
            source_id=source.id,
            source=source,
            published_at=now,
            content_type=ContentType.ARTICLE,
            topics=["sport"],
        )

        ctx = ScoringContext(
            user_profile=None,
            user_interests=set(),
            user_interest_weights={},
            followed_source_ids=set(),
            user_prefs={},
            now=now,
            user_custom_topics=[topic],
        )

        score_match = engine.compute_score(article_match, ctx)
        score_no_match = engine.compute_score(article_no_match, ctx)

        assert score_match > score_no_match
        assert score_match == ScoringWeights.CUSTOM_TOPIC_BASE_BONUS * 2.0
        assert score_no_match == 0.0


# ============================================================
# 7. Suggestions Logic Test (DB)
# ============================================================


class TestSuggestions:
    @pytest.mark.asyncio
    async def test_suggestions_returns_consumed_topics(
        self, db_session, test_user, test_source_curated
    ):
        """Test that suggestions returns topics from consumed articles
        that the user hasn't yet followed."""
        # Create articles with various topics
        for i, topics in enumerate(
            [["ai", "tech"], ["ai", "science"], ["climate", "environment"], ["ai"]]
        ):
            content = Content(
                id=uuid4(),
                title=f"Article {i}",
                url=f"http://example.com/{uuid4()}",
                source_id=test_source_curated.id,
                published_at=datetime.utcnow(),
                content_type=ContentType.ARTICLE,
                topics=topics,
                guid=f"guid-{uuid4()}",
            )
            db_session.add(content)
            await db_session.flush()

            # Mark as consumed by the user
            status = UserContentStatus(
                user_id=test_user.user_id,
                content_id=content.id,
                status=ContentStatus.CONSUMED,
            )
            db_session.add(status)

        await db_session.commit()

        # User follows "climate" already
        followed_topic = UserTopicProfile(
            user_id=test_user.user_id,
            topic_name="Climat",
            slug_parent="climate",
            keywords=["réchauffement"],
        )
        db_session.add(followed_topic)
        await db_session.commit()

        # Query suggestions (simulating the endpoint logic)
        from sqlalchemy import func

        existing_slugs = {"climate"}

        from app.services.ml.classification_service import VALID_TOPIC_SLUGS

        stmt = (
            select(
                func.unnest(Content.topics).label("topic_slug"),
                func.count().label("article_count"),
            )
            .join(
                UserContentStatus,
                (UserContentStatus.content_id == Content.id)
                & (UserContentStatus.user_id == test_user.user_id),
            )
            .where(
                UserContentStatus.status == ContentStatus.CONSUMED,
                Content.topics.isnot(None),
            )
            .group_by("topic_slug")
            .order_by(func.count().desc())
            .limit(20)
        )

        rows = (await db_session.execute(stmt)).all()

        suggestions = []
        for row in rows:
            slug = row.topic_slug
            if slug not in VALID_TOPIC_SLUGS:
                continue
            if slug in existing_slugs:
                continue
            suggestions.append({"slug": slug, "count": row.article_count})
            if len(suggestions) >= 4:
                break

        # "ai" should be the top suggestion (appears 3 times, not followed)
        assert len(suggestions) >= 1
        assert suggestions[0]["slug"] == "ai"
        assert suggestions[0]["count"] == 3

        # "climate" should NOT be in suggestions (already followed)
        suggestion_slugs = {s["slug"] for s in suggestions}
        assert "climate" not in suggestion_slugs
