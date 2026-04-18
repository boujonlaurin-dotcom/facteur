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

    @pytest.mark.asyncio
    async def test_uses_session_maker_and_does_not_touch_injected_session(self):
        """P1 fix — when session_maker is provided, each DB op opens a
        short-lived session. The injected `session` must NOT be used, so
        the pool isn't held during the LLM pipeline.
        cf. docs/bugs/bug-infinite-load-requests.md
        """
        articles = [_make_deep_content("A")]
        short_session = _mock_session_with_articles(articles)

        # session_maker is an async context manager factory
        maker_calls = []

        class _Maker:
            def __call__(self):
                maker_calls.append(1)
                return self

            async def __aenter__(self):
                return short_session

            async def __aexit__(self, *a):
                return None

        injected = AsyncMock()  # Would blow up if used
        injected.execute.side_effect = AssertionError(
            "injected session must NOT be used when session_maker is set"
        )

        llm = MagicMock()
        llm.is_ready = False

        matcher = DeepMatcher(
            injected, llm, _make_config(), session_maker=_Maker()
        )
        result = await matcher._load_deep_articles()

        assert len(result) == 1
        assert len(maker_calls) == 1
        short_session.execute.assert_awaited_once()
        injected.execute.assert_not_called()


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
    async def test_llm_null_index_is_respected(self):
        """When LLM returns null, we trust it — no broader fallback.

        Better no "Pas de recul" than a hors-sujet article. The previous
        broader_fallback would pick the top Jaccard candidate even after
        an explicit LLM rejection, which produced the Nathalie Baye →
        "mines des empires" bug.
        """
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

        # LLM rejection is final.
        assert result[topic.topic_id] is None

    @pytest.mark.asyncio
    async def test_skips_topics_without_deep_angle(self):
        """Topics with null/empty deep_angle must be skipped — no LLM call."""
        articles = [_make_deep_content("Any article")]
        session = _mock_session_with_articles(articles)

        llm = MagicMock()
        llm.is_ready = True
        llm.chat_json = AsyncMock()

        topic_with_angle = _make_topic(topic_id="c1", deep_angle="Modèle social")
        topic_null = SelectedTopic(
            topic_id="c2",
            label="Celeb death",
            selection_reason="Actu people",
            deep_angle=None,
        )
        topic_empty = SelectedTopic(
            topic_id="c3",
            label="Fait divers",
            selection_reason="Actu local",
            deep_angle="  ",
        )

        matcher = DeepMatcher(session, llm, _make_config())
        with patch.object(
            matcher,
            "_prefilter",
            return_value=[(articles[0], 0.5)],
        ):
            # LLM accepts the only matchable topic
            llm.chat_json.return_value = {"selected_index": 0, "reason": "ok"}
            result = await matcher.match_for_topics(
                [topic_with_angle, topic_null, topic_empty]
            )

        assert result[topic_null.topic_id] is None
        assert result[topic_empty.topic_id] is None
        assert result[topic_with_angle.topic_id] is not None
        # Exactly 2 LLM calls (query expansion + evaluation) for the single
        # matchable topic — skipped topics produce zero LLM cost.
        assert llm.chat_json.await_count == 2

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

    def test_rejects_weak_match_below_min_score(self):
        """min_score raised to 0.15: weak matches must be rejected now that
        there is no broader_fallback safety net."""
        article = _make_deep_content("Weak match")
        # Below default min_score (0.15)
        assert DeepMatcher._fallback_pick([(article, 0.10)]) is None
        # Above
        assert DeepMatcher._fallback_pick([(article, 0.20)]) is not None
