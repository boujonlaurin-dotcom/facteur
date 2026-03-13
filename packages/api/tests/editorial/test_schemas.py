"""Tests for editorial pipeline Pydantic schemas."""

from datetime import UTC, datetime
from uuid import uuid4

from app.services.editorial.schemas import (
    ClusterSummary,
    EditorialGlobalContext,
    EditorialPipelineResult,
    EditorialSubject,
    MatchedActuArticle,
    MatchedDeepArticle,
    SelectedTopic,
)


def _make_actu() -> MatchedActuArticle:
    return MatchedActuArticle(
        content_id=uuid4(),
        title="Test actu article",
        source_name="Le Monde",
        source_id=uuid4(),
        is_user_source=True,
        published_at=datetime.now(UTC),
    )


def _make_deep() -> MatchedDeepArticle:
    return MatchedDeepArticle(
        content_id=uuid4(),
        title="Test deep article",
        source_name="The Conversation",
        source_id=uuid4(),
        published_at=datetime.now(UTC),
        match_reason="Relevant analysis",
    )


def _make_subject(**overrides) -> EditorialSubject:
    defaults = {
        "rank": 1,
        "topic_id": "cluster_001",
        "label": "Test subject",
        "selection_reason": "Important topic",
        "deep_angle": "Systemic analysis",
    }
    defaults.update(overrides)
    return EditorialSubject(**defaults)


class TestClusterSummary:
    def test_construct_valid(self):
        cs = ClusterSummary(
            topic_id="c1",
            label="Réforme retraites",
            article_titles=["Article 1", "Article 2"],
            source_count=5,
            is_trending=True,
            theme="politique",
        )
        assert cs.topic_id == "c1"
        assert cs.source_count == 5
        assert cs.is_trending is True

    def test_theme_optional_defaults_none(self):
        cs = ClusterSummary(
            topic_id="c1",
            label="Test",
            article_titles=[],
            source_count=1,
            is_trending=False,
        )
        assert cs.theme is None


class TestSelectedTopic:
    def test_construct_valid(self):
        st = SelectedTopic(
            topic_id="c1",
            label="Le vote décisif",
            selection_reason="Impact direct",
            deep_angle="Modèle social",
        )
        assert st.topic_id == "c1"
        assert st.deep_angle == "Modèle social"


class TestMatchedActuArticle:
    def test_construct_valid(self):
        actu = _make_actu()
        assert actu.is_user_source is True
        assert isinstance(actu.published_at, datetime)


class TestMatchedDeepArticle:
    def test_construct_valid(self):
        deep = _make_deep()
        assert deep.match_reason == "Relevant analysis"


class TestEditorialSubject:
    def test_optional_fields_default_none(self):
        subject = _make_subject()
        assert subject.intro_text is None
        assert subject.transition_text is None
        assert subject.actu_article is None
        assert subject.deep_article is None

    def test_with_articles(self):
        subject = _make_subject(actu_article=_make_actu(), deep_article=_make_deep())
        assert subject.actu_article is not None
        assert subject.deep_article is not None

    def test_json_roundtrip(self):
        subject = _make_subject(actu_article=_make_actu(), deep_article=_make_deep())
        data = subject.model_dump(mode="json")
        restored = EditorialSubject.model_validate(data)
        assert restored.topic_id == subject.topic_id
        assert restored.actu_article.title == subject.actu_article.title
        assert restored.deep_article.match_reason == subject.deep_article.match_reason


class TestEditorialGlobalContext:
    def test_construct_valid(self):
        ctx = EditorialGlobalContext(
            subjects=[_make_subject()],
            cluster_data=[{"cluster_id": "c1", "label": "Test"}],
            generated_at=datetime.now(UTC),
        )
        assert len(ctx.subjects) == 1
        assert len(ctx.cluster_data) == 1

    def test_json_roundtrip(self):
        ctx = EditorialGlobalContext(
            subjects=[_make_subject(actu_article=_make_actu())],
            cluster_data=[{"cluster_id": "c1"}],
            generated_at=datetime.now(UTC),
        )
        data = ctx.model_dump(mode="json")
        restored = EditorialGlobalContext.model_validate(data)
        assert restored.subjects[0].actu_article.title == ctx.subjects[0].actu_article.title


class TestEditorialPipelineResult:
    def test_construct_valid(self):
        result = EditorialPipelineResult(
            subjects=[_make_subject()],
            metadata={"actu_hits": 3, "deep_hits": 2, "total_subjects": 3, "matching_ms": 42.5},
        )
        assert result.metadata["actu_hits"] == 3
        assert len(result.subjects) == 1
