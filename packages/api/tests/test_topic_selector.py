"""Tests unitaires pour TopicSelector — sélection de N sujets du jour.

Couvre:
- select_topics_for_user: pipeline complet
- _score_clusters: scoring topic-level
- _select_n_topics: sélection avec contraintes de diversité
- _build_topic_groups: construction des TopicGroup avec articles
- _score_and_select_articles: scoring et sélection intra-topic
"""

import pytest
import uuid
from datetime import datetime, timezone, timedelta
from unittest.mock import Mock, MagicMock

from app.services.topic_selector import TopicSelector, TopicGroup, ScoredArticle
from app.services.briefing.importance_detector import TopicCluster
from app.services.digest_selector import DigestContext, GlobalTrendingContext
from app.schemas.digest import DigestScoreBreakdown


# ─── Factories ────────────────────────────────────────────────────────────────


def make_source(name="Test Source", theme="tech", is_curated=False):
    source = Mock()
    source.id = uuid.uuid4()
    source.name = name
    source.theme = theme
    source.is_curated = is_curated
    source.reliability_score = None
    source.secondary_themes = []
    return source


def make_content(source=None, title=None, published_at=None, theme=None):
    content = Mock()
    content.id = uuid.uuid4()
    content.source = source or make_source()
    content.source_id = content.source.id
    content.published_at = published_at or datetime.now(timezone.utc)
    content.title = title or f"Article {content.id}"
    content.url = f"https://example.com/{content.id}"
    content.thumbnail_url = None
    content.description = None
    content.topics = []
    content.content_type = "article"
    content.duration_seconds = None
    content.theme = theme
    content.guid = str(uuid.uuid4())
    content.is_paid = False
    return content


def make_cluster(contents, theme=None, cluster_id=None):
    """Create a TopicCluster from a list of mock contents."""
    source_ids = set(c.source_id for c in contents)
    return TopicCluster(
        cluster_id=cluster_id or str(uuid.uuid4()),
        label="",
        tokens={"test", "tokens"},
        contents=contents,
        source_ids=source_ids,
        theme=theme,
    )


def make_context(
    user_id=None,
    followed_source_ids=None,
    user_interests=None,
    user_bias_stance=None,
):
    """Create a minimal DigestContext mock."""
    ctx = Mock(spec=DigestContext)
    ctx.user_id = user_id or uuid.uuid4()
    ctx.followed_source_ids = followed_source_ids or set()
    ctx.user_interests = user_interests or set()
    ctx.user_bias_stance = user_bias_stance
    ctx.muted_source_ids = set()
    ctx.history_content_ids = set()
    ctx.subtopic_weights = {}
    ctx.source_affinity_scores = {}
    ctx.user_subtopics = set()
    ctx.user_subtopic_weights = {}
    return ctx


def make_trending_context(trending_ids=None, une_ids=None):
    ctx = Mock(spec=GlobalTrendingContext)
    ctx.trending_content_ids = trending_ids or set()
    ctx.une_content_ids = une_ids or set()
    return ctx


# ─── Tests ────────────────────────────────────────────────────────────────────


class TestTopicSelectorInit:
    def test_creates_importance_detector(self):
        selector = TopicSelector()
        assert selector.importance_detector is not None


class TestScoreClusters:
    """Tests for _score_clusters."""

    def test_followed_source_bonus(self):
        selector = TopicSelector()
        src = make_source()
        content = make_content(source=src)
        cluster = make_cluster([content], theme="tech")

        context = make_context(followed_source_ids={src.id})
        trending_ctx = make_trending_context()

        scored = selector._score_clusters([cluster], context, trending_ctx, "pour_vous")
        assert len(scored) == 1
        _, score, reason = scored[0]
        assert score > 0
        assert "Sources suivies" in reason

    def test_trending_bonus(self):
        selector = TopicSelector()
        src1, src2, src3 = make_source(), make_source(), make_source()
        c1 = make_content(source=src1)
        c2 = make_content(source=src2)
        c3 = make_content(source=src3)
        cluster = make_cluster([c1, c2, c3])  # 3 sources = trending

        trending_ctx = make_trending_context(trending_ids={c1.id})
        context = make_context()

        scored = selector._score_clusters([cluster], context, trending_ctx, "pour_vous")
        _, score, _ = scored[0]
        # Should include trending bonus
        from app.services.recommendation.scoring_config import ScoringWeights

        assert score >= ScoringWeights.TOPIC_TRENDING_BONUS

    def test_serein_excludes_anxiogenic(self):
        """Mode serein exclut les clusters avec thème politics."""
        selector = TopicSelector()
        src = make_source(theme="politics")
        content = make_content(source=src, theme="politics")
        cluster = make_cluster([content], theme="politics")

        context = make_context()
        trending_ctx = make_trending_context()

        scored = selector._score_clusters([cluster], context, trending_ctx, "serein")
        # Should be excluded (politics is in SEREIN_EXCLUDED_THEMES)
        assert len(scored) == 0

    def test_theme_match_bonus(self):
        selector = TopicSelector()
        src = make_source(theme="tech")
        content = make_content(source=src, theme="tech")
        cluster = make_cluster([content], theme="tech")

        context = make_context(user_interests={"tech"})
        trending_ctx = make_trending_context()

        scored = selector._score_clusters([cluster], context, trending_ctx, "pour_vous")
        _, score, _ = scored[0]
        from app.services.recommendation.scoring_config import ScoringWeights

        assert score >= ScoringWeights.TOPIC_THEME_MATCH_BONUS


class TestSelectNTopics:
    """Tests for _select_n_topics."""

    def test_select_exact_count(self):
        selector = TopicSelector()
        themes = ["tech", "economy", "culture", "science", "politics"]
        clusters = []
        for i in range(5):
            src = make_source(theme=themes[i])
            content = make_content(source=src)
            cluster = make_cluster([content], theme=themes[i])
            clusters.append((cluster, 100 - i * 10, f"Reason {i}"))

        selected = selector._select_n_topics(
            clusters, target_count=3, trending_context=None
        )
        assert len(selected) == 3

    def test_multi_articles_prioritized(self):
        """Multi-article clusters should come before singletons."""
        selector = TopicSelector()

        # Multi-article cluster (lower score)
        src1, src2 = make_source(), make_source()
        c1 = make_content(source=src1)
        c2 = make_content(source=src2)
        multi_cluster = make_cluster([c1, c2])

        # Singleton (higher score)
        src3 = make_source()
        c3 = make_content(source=src3)
        single_cluster = make_cluster([c3])

        scored = [
            (single_cluster, 200.0, "Singleton"),
            (multi_cluster, 100.0, "Multi"),
        ]

        selected = selector._select_n_topics(
            scored, target_count=2, trending_context=None
        )
        # Both should be selected
        assert len(selected) == 2
        # Multi-article should be first
        assert len(selected[0][0].contents) >= 2

    def test_max_2_per_theme(self):
        """No more than 2 topics from the same theme."""
        selector = TopicSelector()

        clusters = []
        for i in range(4):
            src = make_source(theme="tech")
            content = make_content(source=src)
            cluster = make_cluster([content], theme="tech")
            clusters.append((cluster, 100 - i * 10, "Tech topic"))

        selected = selector._select_n_topics(
            clusters, target_count=4, trending_context=None
        )
        # Should only get 2 (max per theme)
        assert len(selected) == 2

    def test_trending_guardrail(self):
        """If no trending in selection but available, replaces last topic."""
        selector = TopicSelector()

        # Non-trending cluster (selected)
        src1 = make_source()
        c1 = make_content(source=src1)
        non_trending = make_cluster([c1])

        # Trending cluster (not selected due to lower score, but should be forced in)
        src_t1, src_t2, src_t3 = make_source(), make_source(), make_source()
        ct1 = make_content(source=src_t1)
        ct2 = make_content(source=src_t2)
        ct3 = make_content(source=src_t3)
        trending = make_cluster([ct1, ct2, ct3], theme="other")

        trending_ctx = make_trending_context(trending_ids={ct1.id})

        scored = [
            (non_trending, 200.0, "Not trending"),
            (trending, 50.0, "Trending"),
        ]

        selected = selector._select_n_topics(
            scored, target_count=1, trending_context=trending_ctx
        )
        # The trending cluster should have replaced the non-trending one
        assert len(selected) == 1
        assert selected[0][0] is trending

    def test_fewer_candidates_than_target(self):
        """Should return all available if fewer than target."""
        selector = TopicSelector()
        src = make_source()
        c = make_content(source=src)
        cluster = make_cluster([c])

        selected = selector._select_n_topics(
            [(cluster, 100.0, "Only one")],
            target_count=5,
            trending_context=None,
        )
        assert len(selected) == 1


class TestTopicMatchScoring:
    """Tests for topic match bonus at cluster and article level."""

    def test_cluster_topic_match_bonus(self):
        """Cluster with article matching user_subtopics gets TOPIC_MATCH bonus."""
        selector = TopicSelector()
        src = make_source(theme="tech")
        content = make_content(source=src, theme="tech")
        content.topics = ["ai", "machine-learning"]
        cluster = make_cluster([content], theme="tech")

        ctx = make_context()
        ctx.user_subtopics = {"ai"}
        ctx.user_subtopic_weights = {"ai": 1.0}
        trending_ctx = make_trending_context()

        scored = selector._score_clusters([cluster], ctx, trending_ctx, "pour_vous")
        assert len(scored) == 1
        _, score, reason = scored[0]
        from app.services.recommendation.scoring_config import ScoringWeights

        assert score >= ScoringWeights.TOPIC_MATCH
        assert "Sujet :" in reason

    def test_cluster_no_topic_match_no_bonus(self):
        """Cluster without matching topics does not get topic match bonus."""
        selector = TopicSelector()
        src = make_source(theme="tech")
        content = make_content(source=src, theme="tech")
        content.topics = ["cinema", "music"]
        cluster = make_cluster([content], theme="tech")

        ctx = make_context()
        ctx.user_subtopics = {"ai", "politics"}
        ctx.user_subtopic_weights = {}
        trending_ctx = make_trending_context()

        scored = selector._score_clusters([cluster], ctx, trending_ctx, "pour_vous")
        _, score, reason = scored[0]
        assert "Sujet :" not in reason

    def test_article_topic_match_scoring(self):
        """Article with topic in user_subtopics gets TOPIC_MATCH bonus."""
        selector = TopicSelector()
        src = make_source(theme="tech")
        content = make_content(source=src, theme="tech")
        content.topics = ["ai"]
        cluster = make_cluster([content], theme="tech")

        ctx = make_context()
        ctx.user_subtopics = {"ai"}
        ctx.user_subtopic_weights = {"ai": 1.0}
        trending_ctx = make_trending_context()

        articles = selector._score_and_select_articles(cluster, ctx, trending_ctx)
        assert len(articles) == 1
        breakdown_labels = [b.label for b in articles[0].breakdown]
        assert any("Sujet :" in lbl for lbl in breakdown_labels)

    def test_article_topic_match_with_weight(self):
        """Weighted subtopic gets multiplied score and 'Renforcé' label."""
        selector = TopicSelector()
        src = make_source(theme="tech")
        content = make_content(source=src, theme="tech")
        content.topics = ["ai"]
        cluster = make_cluster([content], theme="tech")

        ctx = make_context()
        ctx.user_subtopics = {"ai"}
        ctx.user_subtopic_weights = {"ai": 1.5}
        trending_ctx = make_trending_context()

        articles = selector._score_and_select_articles(cluster, ctx, trending_ctx)
        breakdown_labels = [b.label for b in articles[0].breakdown]
        assert any("Renforcé" in lbl for lbl in breakdown_labels)
        # Score should reflect weight multiplier
        topic_bd = [b for b in articles[0].breakdown if "Renforcé" in b.label]
        from app.services.recommendation.scoring_config import ScoringWeights

        assert topic_bd[0].points == ScoringWeights.TOPIC_MATCH * 1.5

    def test_article_topic_max_matches_cap(self):
        """At most TOPIC_MAX_MATCHES topics count toward score."""
        selector = TopicSelector()
        src = make_source(theme="tech")
        content = make_content(source=src, theme="tech")
        content.topics = ["ai", "tech", "cybersecurity"]
        cluster = make_cluster([content], theme="tech")

        ctx = make_context()
        ctx.user_subtopics = {"ai", "tech", "cybersecurity"}
        ctx.user_subtopic_weights = {}
        trending_ctx = make_trending_context()

        articles = selector._score_and_select_articles(cluster, ctx, trending_ctx)
        topic_breakdowns = [b for b in articles[0].breakdown if "Sujet :" in b.label]
        from app.services.recommendation.scoring_config import ScoringWeights

        assert len(topic_breakdowns) == ScoringWeights.TOPIC_MAX_MATCHES  # 2, not 3

    def test_article_precision_bonus(self):
        """Topic match + theme match triggers SUBTOPIC_PRECISION_BONUS."""
        selector = TopicSelector()
        src = make_source(theme="tech")
        content = make_content(source=src, theme="tech")
        content.topics = ["ai"]
        cluster = make_cluster([content], theme="tech")

        ctx = make_context(user_interests={"tech"})
        ctx.user_subtopics = {"ai"}
        ctx.user_subtopic_weights = {"ai": 1.0}
        trending_ctx = make_trending_context()

        articles = selector._score_and_select_articles(cluster, ctx, trending_ctx)
        breakdown_labels = [b.label for b in articles[0].breakdown]
        assert any("Précision" in lbl for lbl in breakdown_labels)

    def test_article_no_precision_bonus_without_theme(self):
        """Topic match without theme match does NOT trigger precision bonus."""
        selector = TopicSelector()
        src = make_source(theme="science")
        content = make_content(source=src, theme="science")
        content.topics = ["ai"]
        cluster = make_cluster([content], theme="science")

        ctx = make_context(user_interests={"tech"})  # tech != science
        ctx.user_subtopics = {"ai"}
        ctx.user_subtopic_weights = {"ai": 1.0}
        trending_ctx = make_trending_context()

        articles = selector._score_and_select_articles(cluster, ctx, trending_ctx)
        breakdown_labels = [b.label for b in articles[0].breakdown]
        assert not any("Précision" in lbl for lbl in breakdown_labels)


class TestScoreAndSelectArticles:
    """Tests for _score_and_select_articles."""

    def test_max_3_articles(self):
        """Should select at most TOPIC_MAX_ARTICLES articles."""
        selector = TopicSelector()
        sources = [make_source() for _ in range(5)]
        contents = [make_content(source=s) for s in sources]
        cluster = make_cluster(contents)

        context = make_context()
        trending_ctx = make_trending_context()

        articles = selector._score_and_select_articles(cluster, context, trending_ctx)
        from app.services.recommendation.scoring_config import ScoringWeights

        assert len(articles) <= ScoringWeights.TOPIC_MAX_ARTICLES

    def test_source_diversity(self):
        """Selected articles should have different sources."""
        selector = TopicSelector()
        src = make_source()
        contents = [make_content(source=src, title=f"Article {i}") for i in range(3)]
        # All from the same source
        cluster = make_cluster(contents)

        context = make_context()
        trending_ctx = make_trending_context()

        articles = selector._score_and_select_articles(cluster, context, trending_ctx)
        # Only 1 article should be selected (source diversity)
        assert len(articles) == 1

    def test_followed_source_flagged(self):
        """Articles from followed sources should have is_followed_source=True."""
        selector = TopicSelector()
        src = make_source()
        content = make_content(source=src)
        cluster = make_cluster([content])

        context = make_context(followed_source_ids={src.id})
        trending_ctx = make_trending_context()

        articles = selector._score_and_select_articles(cluster, context, trending_ctx)
        assert len(articles) == 1
        assert articles[0].is_followed_source is True

    def test_returns_scored_articles(self):
        """Each result should be a ScoredArticle with breakdown."""
        selector = TopicSelector()
        src = make_source()
        content = make_content(source=src, published_at=datetime.now(timezone.utc))
        cluster = make_cluster([content])

        context = make_context()
        trending_ctx = make_trending_context()

        articles = selector._score_and_select_articles(cluster, context, trending_ctx)
        assert len(articles) == 1
        art = articles[0]
        assert isinstance(art, ScoredArticle)
        assert art.content is content
        assert isinstance(art.score, float)
        assert isinstance(art.reason, str)


class TestSelectTopicsForUser:
    """Integration tests for select_topics_for_user."""

    @pytest.mark.asyncio
    async def test_returns_topic_groups(self):
        """Should return a list of TopicGroup."""
        selector = TopicSelector()

        # Create diverse candidates
        sources = [
            make_source(theme=t)
            for t in ["tech", "economy", "culture", "science", "politics"]
        ]
        candidates = []
        for src in sources:
            for i in range(3):
                candidates.append(
                    make_content(
                        source=src,
                        title=f"Article about {src.theme} topic {i}",
                        published_at=datetime.now(timezone.utc)
                        - timedelta(hours=i * 6),
                    )
                )

        context = make_context(
            followed_source_ids={sources[0].id, sources[1].id},
            user_interests={"tech", "economy"},
        )
        trending_ctx = make_trending_context()

        result = await selector.select_topics_for_user(
            candidates=candidates,
            context=context,
            target_topics=3,
            trending_context=trending_ctx,
            mode="pour_vous",
        )

        assert isinstance(result, list)
        assert len(result) <= 3
        for tg in result:
            assert isinstance(tg, TopicGroup)
            assert len(tg.articles) >= 1
            assert tg.label  # Label should be set (title of best article)
            assert tg.topic_id

    @pytest.mark.asyncio
    async def test_empty_candidates(self):
        selector = TopicSelector()
        context = make_context()

        result = await selector.select_topics_for_user(
            candidates=[],
            context=context,
            target_topics=5,
            trending_context=None,
        )
        assert result == []

    @pytest.mark.asyncio
    async def test_each_topic_has_articles(self):
        """Every returned topic should have at least 1 article."""
        selector = TopicSelector()

        sources = [make_source() for _ in range(5)]
        candidates = [make_content(source=s) for s in sources]
        context = make_context()

        result = await selector.select_topics_for_user(
            candidates=candidates,
            context=context,
            target_topics=3,
            trending_context=None,
        )

        for tg in result:
            assert len(tg.articles) >= 1

    @pytest.mark.asyncio
    async def test_topic_label_is_best_article_title(self):
        """Topic label should be the title of the first (best) article."""
        selector = TopicSelector()

        src = make_source()
        content = make_content(source=src, title="The specific article title")
        context = make_context()

        result = await selector.select_topics_for_user(
            candidates=[content],
            context=context,
            target_topics=1,
            trending_context=None,
        )

        assert len(result) == 1
        assert result[0].label == "The specific article title"
