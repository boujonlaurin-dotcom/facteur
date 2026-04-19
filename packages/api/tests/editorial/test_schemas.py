"""Tests for editorial pipeline Pydantic schemas."""

from datetime import UTC, datetime
from uuid import uuid4

from app.schemas.digest import DigestTopic
from app.services.editorial.schemas import (
    ClusterSummary,
    EditorialGlobalContext,
    EditorialPipelineResult,
    EditorialSubject,
    MatchedActuArticle,
    MatchedDeepArticle,
    SelectedTopic,
    compute_bias_distribution,
    compute_bias_highlights,
)


class _FakePerspective:
    """Minimal stand-in for app.services.perspective_service.Perspective."""

    def __init__(self, bias_stance: str):
        self.bias_stance = bias_stance


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

    def test_deep_angle_optional_for_eventful_topics(self):
        """People / faits divers / event-only topics can opt out of deep
        matching by setting deep_angle to None, which DeepMatcher will
        skip."""
        st = SelectedTopic(
            topic_id="c1",
            label="Mort d'une célébrité",
            selection_reason="Actu people",
            deep_angle=None,
        )
        assert st.deep_angle is None
        # Default when omitted entirely.
        st2 = SelectedTopic(
            topic_id="c2",
            label="Foot: match du soir",
            selection_reason="Actu sportive",
        )
        assert st2.deep_angle is None


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


class TestComputeBiasHighlights:
    """Tests for compute_bias_highlights() — aggregates left/right before comparing."""

    def test_total_zero(self):
        dist = {"left": 0, "center-left": 0, "center": 0, "center-right": 0, "right": 0}
        assert compute_bias_highlights(dist) == "Aucune source trouvée"

    def test_no_left_media(self):
        # left+center-left=0, right=3 → "Aucun média de gauche"
        dist = {"left": 0, "center-left": 0, "center": 1, "center-right": 1, "right": 2}
        assert compute_bias_highlights(dist) == "Aucun média de gauche"

    def test_no_right_media(self):
        # right+center-right=0, left=2 → "Aucun média de droite"
        dist = {"left": 1, "center-left": 1, "center": 2, "center-right": 0, "right": 0}
        assert compute_bias_highlights(dist) == "Aucun média de droite"

    def test_no_right_but_left_below_threshold(self):
        # right=0 but left=1 (< 2) → NOT "Aucun média de droite", falls through to balanced
        dist = {"left": 1, "center-left": 0, "center": 1, "center-right": 0, "right": 0}
        assert compute_bias_highlights(dist) == "Couverture équilibrée"

    def test_heavily_left(self):
        # left aggregate > 60%
        dist = {"left": 4, "center-left": 2, "center": 1, "center-right": 0, "right": 0}
        # left=6/7 = 85% > 60%, but also right=0, left>=2 → "Aucun média de droite" triggers first
        assert compute_bias_highlights(dist) == "Aucun média de droite"

    def test_dominant_left_with_some_right(self):
        # left > 60% but right > 0
        dist = {"left": 5, "center-left": 2, "center": 1, "center-right": 1, "right": 1}
        # left=7/10 = 70% > 60%
        assert compute_bias_highlights(dist) == "Très couvert à gauche"

    def test_dominant_right(self):
        # right aggregate > 60%
        dist = {"left": 1, "center-left": 0, "center": 1, "center-right": 3, "right": 4}
        # right=7/9 ≈ 78% > 60%
        assert compute_bias_highlights(dist) == "Très couvert à droite"

    def test_balanced(self):
        dist = {"left": 2, "center-left": 1, "center": 2, "center-right": 1, "right": 2}
        assert compute_bias_highlights(dist) == "Couverture équilibrée"

    def test_only_center(self):
        dist = {"left": 0, "center-left": 0, "center": 5, "center-right": 0, "right": 0}
        # both sides = 0, but neither has the other >= 2
        assert compute_bias_highlights(dist) == "Couverture équilibrée"


class TestEditorialSubjectPerspectiveFields:
    """Tests for EditorialSubject with perspective fields."""

    def test_defaults_without_perspective_fields(self):
        subject = _make_subject()
        assert subject.perspective_count == 0
        assert subject.bias_distribution is None
        assert subject.bias_highlights is None
        assert subject.divergence_analysis is None

    def test_with_perspective_fields(self):
        subject = _make_subject(
            perspective_count=7,
            bias_distribution={"left": 2, "center-left": 1, "center": 2, "center-right": 1, "right": 1},
            bias_highlights="Couverture équilibrée",
            divergence_analysis="Les médias divergent sur l'impact économique.",
        )
        assert subject.perspective_count == 7
        assert subject.bias_distribution["left"] == 2
        assert subject.bias_highlights == "Couverture équilibrée"
        assert subject.divergence_analysis is not None

    def test_json_roundtrip_with_perspective_fields(self):
        subject = _make_subject(
            perspective_count=5,
            bias_distribution={"left": 1, "center-left": 0, "center": 3, "center-right": 0, "right": 1},
            bias_highlights="Couverture équilibrée",
            divergence_analysis="Analyse des divergences.",
        )
        data = subject.model_dump(mode="json")
        restored = EditorialSubject.model_validate(data)
        assert restored.perspective_count == 5
        assert restored.bias_distribution == subject.bias_distribution
        assert restored.bias_highlights == "Couverture équilibrée"
        assert restored.divergence_analysis == "Analyse des divergences."

    def test_json_without_perspective_fields_backward_compat(self):
        """Old JSON without perspective fields should parse with defaults."""
        old_json = {
            "rank": 1,
            "topic_id": "c1",
            "label": "Old subject",
            "selection_reason": "Important",
            "deep_angle": "Analysis",
        }
        subject = EditorialSubject.model_validate(old_json)
        assert subject.perspective_count == 0
        assert subject.bias_distribution is None
        assert subject.bias_highlights is None
        assert subject.divergence_analysis is None
        # New field also defaults to None on legacy payloads
        assert subject.representative_content_id is None

    def test_representative_content_id_roundtrip(self):
        cid = uuid4()
        subject = _make_subject(representative_content_id=cid)
        data = subject.model_dump(mode="json")
        restored = EditorialSubject.model_validate(data)
        assert str(restored.representative_content_id) == str(cid)


class TestComputeBiasDistributionAlignment:
    """Invariant test backing the 3-counter alignment fix.

    The pipeline filters out perspectives with bias_stance == 'unknown' BEFORE
    setting perspective_count and bias_distribution, so the digest header,
    spectrum bar and bottom-sheet all converge on the same value.
    """

    def test_excludes_unknown_perspectives(self):
        perspectives = [
            _FakePerspective("left"),
            _FakePerspective("center"),
            _FakePerspective("right"),
            _FakePerspective("unknown"),
            _FakePerspective("unknown"),
        ]
        dist = compute_bias_distribution(perspectives)
        assert sum(dist.values()) == 3
        # No "unknown" key leaks into the distribution
        assert "unknown" not in dist

    def test_count_matches_distribution_sum(self):
        """Mirror of pipeline.py: filter then count — they must agree."""
        perspectives = [
            _FakePerspective("left"),
            _FakePerspective("center-left"),
            _FakePerspective("right"),
            _FakePerspective("unknown"),
        ]
        known = [p for p in perspectives if p.bias_stance != "unknown"]
        dist = compute_bias_distribution(known)
        # Invariant: header count == sum of bar segments
        assert len(known) == sum(dist.values())


class TestDigestTopicBackwardCompat:
    """Old digest JSON (3 subjects, no perspective fields) must parse without error."""

    def test_old_digest_topic_without_perspective_fields(self):
        old_topic = {
            "topic_id": "c1",
            "label": "Old topic",
            "rank": 1,
            "reason": "Selected",
            "is_trending": True,
            "source_count": 3,
            "articles": [],
        }
        topic = DigestTopic.model_validate(old_topic)
        assert topic.perspective_count == 0
        assert topic.bias_distribution is None
        assert topic.bias_highlights is None
        assert topic.divergence_analysis is None

    def test_new_digest_topic_with_perspective_fields(self):
        new_topic = {
            "topic_id": "c1",
            "label": "New topic",
            "rank": 1,
            "reason": "Selected",
            "perspective_count": 8,
            "bias_distribution": {"left": 2, "center-left": 1, "center": 3, "center-right": 1, "right": 1},
            "bias_highlights": "Couverture équilibrée",
            "divergence_analysis": "Les médias divergent.",
            "articles": [],
        }
        topic = DigestTopic.model_validate(new_topic)
        assert topic.perspective_count == 8
        assert topic.bias_distribution["left"] == 2
        assert topic.divergence_analysis == "Les médias divergent."

    def test_digest_topic_representative_content_id_optional(self):
        """Legacy cached digests have no representative_content_id."""
        legacy_topic = {
            "topic_id": "c1",
            "label": "Legacy",
            "rank": 1,
            "reason": "Selected",
            "articles": [],
        }
        topic = DigestTopic.model_validate(legacy_topic)
        assert topic.representative_content_id is None

    def test_digest_topic_representative_content_id_propagates(self):
        cid = str(uuid4())
        new_topic = {
            "topic_id": "c1",
            "label": "Fresh",
            "rank": 1,
            "reason": "Selected",
            "articles": [],
            "representative_content_id": cid,
        }
        topic = DigestTopic.model_validate(new_topic)
        assert topic.representative_content_id == cid
