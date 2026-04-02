"""Tests for DeepMatcher (ÉTAPE 3B — deep source article matching)."""

from datetime import UTC, datetime
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

import pytest

from app.services.editorial.config import EditorialConfig, PipelineConfig, PromptConfig
from app.services.editorial.deep_matcher import DeepMatcher
from app.services.editorial.schemas import MatchedDeepArticle, SelectedTopic


def _make_config() -> EditorialConfig:
    return EditorialConfig(
        pipeline=PipelineConfig(
            deep_candidates_prefilter=10,
            deep_jaccard_threshold=0.10,
        ),
        deep_matching_prompt=PromptConfig(
            system="Find deep articles about {topic_label}: {deep_angle}",
            temperature=0.2,
            max_tokens=300,
        ),
    )


def _make_topic(topic_id: str = "c1", label: str = "Retraites réforme", deep_angle: str = "Modèle social") -> SelectedTopic:
    return SelectedTopic(
        topic_id=topic_id,
        label=label,
        selection_reason="Important",
        deep_angle=deep_angle,
    )


def _make_deep_content(
    title: str = "Deep analysis article",
    source_name: str = "The Conversation",
    topics: list[str] | None = None,
):
    c = MagicMock()
    c.id = uuid4()
    c.title = title
    c.source_id = uuid4()
    c.source = MagicMock()
    c.source.name = source_name
    c.published_at = datetime.now(UTC)
    c.is_paid = False
    c.description = f"Analysis: {title}"
    c.topics = topics or []
    return c


def _mock_session_with_articles(articles: list) -> AsyncMock:
    session = AsyncMock()
    mock_result = MagicMock()
    mock_scalars = MagicMock()
    mock_scalars.all.return_value = articles
    mock_result.scalars.return_value = mock_scalars
    session.execute = AsyncMock(return_value=mock_result)
    return session


class TestLoadDeepArticles:
    @pytest.mark.asyncio
    async def test_loads_articles(self):
        articles = [_make_deep_content("Article 1"), _make_deep_content("Article 2")]
        session = _mock_session_with_articles(articles)
        llm = MagicMock()
        llm.is_ready = False

        matcher = DeepMatcher(session, llm, _make_config())
        result = await matcher._load_deep_articles()

        assert len(result) == 2
        session.execute.assert_awaited_once()


class TestPrefilter:
    def test_filters_by_jaccard_threshold(self):
        session = AsyncMock()
        llm = MagicMock()
        config = _make_config()

        matcher = DeepMatcher(session, llm, config)
        topic = _make_topic(label="retraites reforme", deep_angle="modele social")

        # Article with overlapping terms should pass
        relevant = _make_deep_content(title="Réforme des retraites analyse")
        # Article with no overlap should fail
        irrelevant = _make_deep_content(title="Football match résultats ligue")

        candidates = matcher._prefilter(
            topic=topic,
            articles=[relevant, irrelevant],
            limit=10,
            threshold=0.10,
        )

        # At least the relevant article should be included
        content_ids = {c.id for c, _ in candidates}
        assert relevant.id in content_ids

    def test_respects_limit(self):
        session = AsyncMock()
        llm = MagicMock()
        config = _make_config()

        matcher = DeepMatcher(session, llm, config)
        topic = _make_topic(label="retraites reforme modele social protection")

        # Create many articles with similar titles
        articles = [_make_deep_content(title=f"Retraites reforme article {i}") for i in range(20)]

        candidates = matcher._prefilter(
            topic=topic,
            articles=articles,
            limit=5,
            threshold=0.0,  # Accept all for this test
        )

        assert len(candidates) <= 5


class TestMatchForTopics:
    @pytest.mark.asyncio
    async def test_llm_selects_article(self):
        articles = [
            _make_deep_content("Modèle retraite scandinave"),
            _make_deep_content("Financement retraites répartition"),
        ]
        session = _mock_session_with_articles(articles)

        llm = MagicMock()
        llm.is_ready = True
        llm.chat_json = AsyncMock(return_value={
            "selected_index": 1,
            "reason": "Directly relevant analysis",
        })

        topic = _make_topic()
        matcher = DeepMatcher(session, llm, _make_config())

        # Patch _prefilter to return our articles as candidates
        with patch.object(
            matcher, "_prefilter",
            return_value=[(articles[0], 0.5), (articles[1], 0.4)],
        ):
            result = await matcher.match_for_topics([topic])

        assert topic.topic_id in result
        match = result[topic.topic_id]
        assert isinstance(match, MatchedDeepArticle)
        assert match.content_id == articles[1].id
        assert match.match_reason == "Directly relevant analysis"

    @pytest.mark.asyncio
    async def test_llm_null_index_broader_fallback(self):
        """When LLM returns null, broader fallback (pass 3) picks best Jaccard."""
        articles = [_make_deep_content("Some article")]
        session = _mock_session_with_articles(articles)

        llm = MagicMock()
        llm.is_ready = True
        llm.chat_json = AsyncMock(return_value={
            "selected_index": None,
            "reason": "No good match",
        })

        topic = _make_topic()
        matcher = DeepMatcher(session, llm, _make_config())

        with patch.object(
            matcher, "_prefilter",
            return_value=[(articles[0], 0.3)],
        ):
            result = await matcher.match_for_topics([topic])

        # Pass 3 broader fallback should find the article
        assert result[topic.topic_id] is not None
        assert result[topic.topic_id].content_id == articles[0].id

    @pytest.mark.asyncio
    async def test_llm_fail_fallback_jaccard(self):
        articles = [_make_deep_content("Best match article")]
        session = _mock_session_with_articles(articles)

        llm = MagicMock()
        llm.is_ready = True
        llm.chat_json = AsyncMock(return_value=None)  # LLM failure

        topic = _make_topic()
        matcher = DeepMatcher(session, llm, _make_config())

        with patch.object(
            matcher, "_prefilter",
            return_value=[(articles[0], 0.5)],
        ):
            result = await matcher.match_for_topics([topic])

        # Should fallback to top Jaccard candidate
        match = result[topic.topic_id]
        assert match is not None
        assert match.content_id == articles[0].id
        assert "automatique" in match.match_reason.lower()

    @pytest.mark.asyncio
    async def test_no_candidates_returns_none(self):
        session = _mock_session_with_articles([])
        llm = MagicMock()
        llm.is_ready = True

        topic = _make_topic()
        matcher = DeepMatcher(session, llm, _make_config())

        result = await matcher.match_for_topics([topic])

        assert result[topic.topic_id] is None

    @pytest.mark.asyncio
    async def test_no_llm_fallback_all(self):
        articles = [_make_deep_content("Fallback article")]
        session = _mock_session_with_articles(articles)

        llm = MagicMock()
        llm.is_ready = False  # No LLM available

        topic = _make_topic()
        matcher = DeepMatcher(session, llm, _make_config())

        with patch.object(
            matcher, "_prefilter",
            return_value=[(articles[0], 0.5)],
        ):
            result = await matcher.match_for_topics([topic])

        match = result[topic.topic_id]
        assert match is not None
        assert match.content_id == articles[0].id
        llm.chat_json.assert_not_called()


class TestFallbackPick:
    def test_returns_top_candidate(self):
        article = _make_deep_content("Top match")
        result = DeepMatcher._fallback_pick([(article, 0.8)])

        assert isinstance(result, MatchedDeepArticle)
        assert result.content_id == article.id

    def test_empty_candidates_returns_none(self):
        result = DeepMatcher._fallback_pick([])
        assert result is None
