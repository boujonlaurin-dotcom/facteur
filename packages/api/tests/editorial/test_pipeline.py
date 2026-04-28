"""Tests for EditorialPipelineService (pipeline orchestrator)."""

from datetime import UTC, datetime
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import UUID, uuid4

import pytest

from app.services.editorial.schemas import (
    EditorialGlobalContext,
    EditorialPipelineResult,
    EditorialSubject,
    MatchedActuArticle,
    MatchedDeepArticle,
    SelectedTopic,
)


def _make_content_mock(title="Test article"):
    c = MagicMock()
    c.id = uuid4()
    c.title = title
    c.source_id = uuid4()
    c.source = MagicMock()
    c.source.name = "Test Source"
    c.published_at = datetime.now(UTC)
    c.is_paid = False
    return c


def _make_cluster_mock(cluster_id="c1", label="Test cluster", contents=None, source_ids=None, theme="politique"):
    cluster = MagicMock()
    cluster.cluster_id = cluster_id
    cluster.label = label
    cluster.contents = contents or [_make_content_mock()]
    cluster.source_ids = source_ids or {uuid4()}
    cluster.theme = theme
    cluster.is_trending = True
    return cluster


def _make_subject(rank=1, topic_id="c1", deep_article=None, actu_article=None):
    return EditorialSubject(
        rank=rank,
        topic_id=topic_id,
        label="Test subject",
        selection_reason="Important",
        deep_angle="Systemic angle",
        deep_article=deep_article,
        actu_article=actu_article,
    )


@pytest.fixture
def mock_dependencies():
    """Patch all external dependencies of EditorialPipelineService."""
    with (
        patch("app.services.editorial.pipeline.load_editorial_config") as mock_config,
        patch("app.services.editorial.pipeline.EditorialLLMClient") as mock_llm_cls,
        patch("app.services.editorial.pipeline.CurationService") as mock_curation_cls,
        patch("app.services.editorial.pipeline.DeepMatcher") as mock_deep_cls,
        patch("app.services.editorial.pipeline.ActuMatcher") as mock_actu_cls,
        patch("app.services.editorial.pipeline.PerspectiveService") as mock_perspective_cls,
    ):
        # Config
        from app.services.editorial.config import EditorialConfig, PipelineConfig
        config = EditorialConfig(
            pipeline=PipelineConfig(),
        )
        mock_config.return_value = config

        # LLM
        mock_llm = MagicMock()
        mock_llm.is_ready = True
        mock_llm.close = AsyncMock()
        mock_llm_cls.return_value = mock_llm

        # Curation
        mock_curation = MagicMock()
        mock_curation.select_topics = AsyncMock()
        mock_curation.select_a_la_une = AsyncMock(return_value=None)
        mock_curation_cls.return_value = mock_curation

        # Deep matcher
        mock_deep = MagicMock()
        mock_deep.match_for_topics = AsyncMock()
        mock_deep_cls.return_value = mock_deep

        # Actu matcher
        mock_actu = MagicMock()
        mock_actu_cls.return_value = mock_actu

        # Perspective service
        mock_perspective = MagicMock()
        mock_perspective.get_perspectives_hybrid = AsyncMock(return_value=([], []))
        mock_perspective.resolve_bias = AsyncMock(return_value="center")
        mock_perspective.analyze_divergences = AsyncMock(return_value=None)
        mock_perspective_cls.return_value = mock_perspective

        yield {
            "config": config,
            "llm": mock_llm,
            "curation": mock_curation,
            "deep": mock_deep,
            "actu": mock_actu,
            "perspective": mock_perspective,
        }


class TestComputeGlobalContext:
    @pytest.mark.asyncio
    async def test_happy_path(self, mock_dependencies):
        from app.services.editorial.pipeline import EditorialPipelineService

        session = AsyncMock()
        svc = EditorialPipelineService(session)

        # Mock ImportanceDetector
        clusters = [
            _make_cluster_mock("c1", "Retraites"),
            _make_cluster_mock("c2", "Inflation", theme="economie"),
            _make_cluster_mock("c3", "Climat", theme="environnement"),
            _make_cluster_mock("c4", "Education", theme="societe"),
            _make_cluster_mock("c5", "Tech", theme="technologie"),
        ]
        with patch("app.services.editorial.pipeline.ImportanceDetector") as mock_detector_cls:
            mock_detector = MagicMock()
            mock_detector.build_topic_clusters.return_value = clusters
            mock_detector_cls.return_value = mock_detector

            # Mock curation: À la Une picks c1, LLM picks remaining 4
            mock_dependencies["curation"].select_a_la_une.return_value = SelectedTopic(
                topic_id="c1", label="Retraites", selection_reason="Traité par 1 sources",
                deep_angle="D", source_count=1,
            )
            remaining_topics = [
                SelectedTopic(topic_id="c2", label="Inflation", selection_reason="R", deep_angle="D"),
                SelectedTopic(topic_id="c3", label="Climat", selection_reason="R", deep_angle="D"),
                SelectedTopic(topic_id="c4", label="Education", selection_reason="R", deep_angle="D"),
                SelectedTopic(topic_id="c5", label="Tech", selection_reason="R", deep_angle="D"),
            ]
            mock_dependencies["curation"].select_topics.return_value = remaining_topics

            # Mock deep matching
            deep_1 = MagicMock(spec=MatchedDeepArticle)
            deep_1.content_id = UUID("00000000-0000-0000-0000-000000000001")
            deep_1.source_id = UUID("00000000-0000-0000-0000-aaaaaaaaaaaa")
            deep_3 = MagicMock(spec=MatchedDeepArticle)
            deep_3.content_id = UUID("00000000-0000-0000-0000-000000000003")
            deep_3.source_id = UUID("00000000-0000-0000-0000-bbbbbbbbbbbb")
            mock_dependencies["deep"].match_for_topics.return_value = {
                "c1": deep_1,
                "c2": None,
                "c3": deep_3,
                "c4": None,
                "c5": None,
            }

            # match_global is now called in global phase — pass subjects through
            mock_dependencies["actu"].match_global.side_effect = (
                lambda subjects, clusters, excluded_source_ids=None, excluded_content_ids=None: subjects
            )

            contents = [_make_content_mock() for _ in range(10)]
            result = await svc.compute_global_context(contents)

        assert result is not None
        assert isinstance(result, EditorialGlobalContext)
        assert len(result.subjects) == 5
        assert result.subjects[0].topic_id == "c1"
        assert result.generated_at is not None

    @pytest.mark.asyncio
    async def test_null_deep_angle_does_not_crash_pipeline(self, mock_dependencies):
        """Regression: curation prompt authorizes deep_angle=null for
        people/faits-divers; the pipeline must accept it end-to-end without
        Pydantic validation errors (EditorialSubject.deep_angle is Optional)."""
        from app.services.editorial.pipeline import EditorialPipelineService

        session = AsyncMock()
        svc = EditorialPipelineService(session)

        cluster = _make_cluster_mock("c1", "Mort d'une célébrité")
        cluster.is_trending = False

        with patch("app.services.editorial.pipeline.ImportanceDetector") as mock_detector_cls:
            mock_detector = MagicMock()
            mock_detector.build_topic_clusters.return_value = [cluster]
            mock_detector_cls.return_value = mock_detector

            # LLM explicitly sets deep_angle=None (valid per the fix).
            mock_dependencies["curation"].select_topics.return_value = [
                SelectedTopic(
                    topic_id="c1",
                    label="Mort d'une célébrité",
                    selection_reason="Actu people",
                    deep_angle=None,
                )
            ]
            mock_dependencies["deep"].match_for_topics.return_value = {"c1": None}
            mock_dependencies["actu"].match_global.side_effect = (
                lambda subjects, clusters, excluded_source_ids=None, excluded_content_ids=None: subjects
            )

            result = await svc.compute_global_context([_make_content_mock()])

        assert result is not None
        assert result.subjects[0].deep_angle is None

    @pytest.mark.asyncio
    async def test_no_clusters_returns_none(self, mock_dependencies):
        from app.services.editorial.pipeline import EditorialPipelineService

        session = AsyncMock()
        svc = EditorialPipelineService(session)

        with patch("app.services.editorial.pipeline.ImportanceDetector") as mock_detector_cls:
            mock_detector = MagicMock()
            mock_detector.build_topic_clusters.return_value = []
            mock_detector_cls.return_value = mock_detector

            result = await svc.compute_global_context([])

        assert result is None

    @pytest.mark.asyncio
    async def test_curation_fails_returns_none(self, mock_dependencies):
        from app.services.editorial.pipeline import EditorialPipelineService

        session = AsyncMock()
        svc = EditorialPipelineService(session)

        # Non-trending cluster — no À la Une fallback
        cluster = _make_cluster_mock()
        cluster.is_trending = False

        with patch("app.services.editorial.pipeline.ImportanceDetector") as mock_detector_cls:
            mock_detector = MagicMock()
            mock_detector.build_topic_clusters.return_value = [cluster]
            mock_detector_cls.return_value = mock_detector

            mock_dependencies["curation"].select_topics.return_value = []

            result = await svc.compute_global_context([_make_content_mock()])

        assert result is None


class TestRunForUser:
    def test_populates_actu_articles(self, mock_dependencies):
        from app.services.editorial.pipeline import EditorialPipelineService

        session = AsyncMock()
        svc = EditorialPipelineService(session)

        subject_with_actu = _make_subject(
            rank=1,
            actu_article=MatchedActuArticle(
                content_id=uuid4(),
                title="Actu",
                source_name="Le Monde",
                source_id=uuid4(),
                is_user_source=True,
                published_at=datetime.now(UTC),
            ),
        )

        mock_dependencies["actu"].match_for_user.return_value = [subject_with_actu]

        global_ctx = EditorialGlobalContext(
            subjects=[_make_subject()],
            cluster_data=[{"cluster_id": "c1"}],
            generated_at=datetime.now(UTC),
        )

        result = svc.run_for_user(
            global_ctx=global_ctx,
            clusters=[_make_cluster_mock()],
            user_source_ids={uuid4()},
            excluded_content_ids=set(),
        )

        assert isinstance(result, EditorialPipelineResult)
        assert result.metadata["actu_hits"] == 1
        assert result.metadata["total_subjects"] == 1
        assert "matching_ms" in result.metadata

    def test_metadata_deep_hits(self, mock_dependencies):
        from app.services.editorial.pipeline import EditorialPipelineService

        session = AsyncMock()
        svc = EditorialPipelineService(session)

        deep = MatchedDeepArticle(
            content_id=uuid4(),
            title="Deep",
            source_name="Src",
            source_id=uuid4(),
            published_at=datetime.now(UTC),
            match_reason="Relevant",
        )
        subjects = [
            _make_subject(rank=1, deep_article=deep),
            _make_subject(rank=2, topic_id="c2"),
        ]
        mock_dependencies["actu"].match_for_user.return_value = subjects

        global_ctx = EditorialGlobalContext(
            subjects=subjects,
            cluster_data=[],
            generated_at=datetime.now(UTC),
        )

        result = svc.run_for_user(
            global_ctx=global_ctx,
            clusters=[],
            user_source_ids=set(),
            excluded_content_ids=set(),
        )

        assert result.metadata["deep_hits"] == 1
        assert result.metadata["total_subjects"] == 2


class _StubPerspective:
    """Stand-in matching the attributes the pipeline reads on a Perspective."""

    def __init__(self, bias_stance: str, source_name: str = "Stub", source_domain: str = "stub.example"):
        self.bias_stance = bias_stance
        self.source_name = source_name
        self.source_domain = source_domain
        self.title = "stub title"
        self.url = "https://stub.example/x"
        self.published_at = None
        self.description = None


class TestPerspectiveCountAlignment:
    """Regression coverage for the 3-counter alignment fix.

    The pipeline must:
      1. Include the cluster's own sources in ``perspective_count`` so the
         header reflects the carousel coverage (not just Google News).
      2. De-duplicate Google News domains already present in the cluster —
         no double-counting.
      3. Filter out ``unknown`` bias before computing ``perspective_count``
         so ``sum(bias_distribution.values()) == perspective_count`` (header
         vs spectrum bar invariant from PR #390).
      4. Persist the cluster's most-recent content id as
         ``representative_content_id`` so the mobile bottom sheet re-fetches
         on the same pivot.
    """

    @pytest.mark.asyncio
    async def test_cluster_perspectives_merged_with_gnews(self, mock_dependencies):
        from app.services.editorial.pipeline import EditorialPipelineService

        # Two cluster contents sharing one source (same outlet, two articles).
        # Cluster source has a resolvable domain.
        shared_source_id = uuid4()
        older = _make_content_mock(title="older")
        older.published_at = datetime(2026, 4, 1, tzinfo=UTC)
        older.source_id = shared_source_id
        older.source.url = "https://www.cluster.fr/"
        older.url = "https://www.cluster.fr/older"

        newer = _make_content_mock(title="newer")
        newer.published_at = datetime(2026, 4, 12, tzinfo=UTC)
        newer.source_id = shared_source_id
        newer.source.url = "https://www.cluster.fr/"
        newer.url = "https://www.cluster.fr/newer"

        cluster = _make_cluster_mock(
            cluster_id="c1",
            label="Retraites",
            contents=[older, newer],
        )

        # resolve_bias: "center" for cluster.fr, look-up map for GNews hosts.
        async def _resolve(domain: str, source_name: str | None = None) -> str:
            if domain == "cluster.fr":
                return "center"
            return {
                "left.fr": "left",
                "center.fr": "center",
                "right.fr": "right",
                "overlap.fr": "center-left",  # same domain also surfaced by GNews
            }.get(domain, "unknown")

        mock_dependencies["perspective"].resolve_bias = AsyncMock(side_effect=_resolve)

        # Google News returns 5 entries (3 known, 2 unknown) + 1 duplicate
        # of cluster domain that must be de-duplicated.
        mock_dependencies["perspective"].get_perspectives_hybrid = AsyncMock(
            return_value=(
                [
                    _StubPerspective("left", "L", "left.fr"),
                    _StubPerspective("center", "C", "center.fr"),
                    _StubPerspective("right", "R", "right.fr"),
                    _StubPerspective("unknown", "U1", "u1.fr"),
                    _StubPerspective("unknown", "U2", "u2.fr"),
                    # Same domain as cluster — must be filtered out.
                    _StubPerspective("center", "Dup", "cluster.fr"),
                ],
                [],
            )
        )

        session = AsyncMock()
        session.execute = AsyncMock(
            return_value=MagicMock(all=MagicMock(return_value=[]))
        )
        svc = EditorialPipelineService(session)

        with patch(
            "app.services.editorial.pipeline.ImportanceDetector"
        ) as mock_detector_cls:
            mock_detector = MagicMock()
            mock_detector.build_topic_clusters.return_value = [cluster]
            mock_detector_cls.return_value = mock_detector

            mock_dependencies["curation"].select_a_la_une.return_value = SelectedTopic(
                topic_id="c1",
                label="Retraites",
                selection_reason="Traité par 1 sources",
                deep_angle="D",
                source_count=1,
            )
            mock_dependencies["curation"].select_topics.return_value = []
            mock_dependencies["deep"].match_for_topics.return_value = {"c1": None}
            mock_dependencies["actu"].match_global.side_effect = (
                lambda subjects, clusters, excluded_source_ids=None, excluded_content_ids=None: subjects
            )

            result = await svc.compute_global_context([older, newer])

        assert result is not None
        subject = result.subjects[0]

        # 1 cluster source (center) + 3 new GNews known (left, center, right)
        # = 4 known. GNews duplicate on cluster.fr must be filtered out.
        assert subject.perspective_count == 4
        assert subject.bias_distribution is not None
        # Invariant preserved.
        assert sum(subject.bias_distribution.values()) == subject.perspective_count
        # Breakdown: 1 left, 2 center (cluster + GNews), 1 right.
        assert subject.bias_distribution["left"] == 1
        assert subject.bias_distribution["center"] == 2
        assert subject.bias_distribution["right"] == 1

        # Pivot = most recent content of the cluster.
        assert subject.representative_content_id == newer.id

    @pytest.mark.asyncio
    async def test_safety_net_counts_cluster_sources_when_all_bias_unknown(
        self, mock_dependencies
    ):
        """Safety net (Axe 2, bug-digest-perspective-undercount):
        when every merged perspective has bias_stance="unknown" but the
        cluster actually grouped several outlets, ``perspective_count``
        must fall back to the cluster source count instead of collapsing
        to 0. bias_distribution stays all-zero so the spectrum bar and
        LLM analysis remain hidden (we don't fake a bias signal).
        """
        from app.services.editorial.pipeline import EditorialPipelineService

        # Two cluster articles, different outlets, both with bias unknown.
        outlet_a_id = uuid4()
        outlet_b_id = uuid4()
        article_a = _make_content_mock(title="outlet A")
        article_a.source_id = outlet_a_id
        article_a.source.url = "https://www.outlet-a.fr/"
        article_a.url = "https://www.outlet-a.fr/story"
        article_a.published_at = datetime(2026, 4, 22, 6, tzinfo=UTC)

        article_b = _make_content_mock(title="outlet B")
        article_b.source_id = outlet_b_id
        article_b.source.url = "https://www.outlet-b.fr/"
        article_b.url = "https://www.outlet-b.fr/story"
        article_b.published_at = datetime(2026, 4, 22, 7, tzinfo=UTC)

        cluster = _make_cluster_mock(
            cluster_id="c1",
            label="Breaking news",
            contents=[article_a, article_b],
            source_ids={outlet_a_id, outlet_b_id},
        )

        # Every resolved bias is unknown (neither outlet in DOMAIN_BIAS_MAP,
        # no DB match). Also pass through Google News articles unknown.
        mock_dependencies["perspective"].resolve_bias = AsyncMock(return_value="unknown")
        mock_dependencies["perspective"].get_perspectives_hybrid = AsyncMock(
            return_value=([], [])
        )
        # Explicit cluster perspectives — 2 outlets, both bias=unknown.
        # Without this override, MagicMock returns a non-awaitable sentinel
        # and the pipeline's try/except swallows it as [], which would
        # short-circuit the safety net we want to exercise.
        mock_dependencies["perspective"].build_cluster_perspectives = AsyncMock(
            return_value=[
                _StubPerspective("unknown", "Outlet A", "outlet-a.fr"),
                _StubPerspective("unknown", "Outlet B", "outlet-b.fr"),
            ]
        )

        session = AsyncMock()
        session.execute = AsyncMock(
            return_value=MagicMock(all=MagicMock(return_value=[]))
        )
        svc = EditorialPipelineService(session)

        with patch(
            "app.services.editorial.pipeline.ImportanceDetector"
        ) as mock_detector_cls:
            mock_detector = MagicMock()
            mock_detector.build_topic_clusters.return_value = [cluster]
            mock_detector_cls.return_value = mock_detector

            mock_dependencies["curation"].select_a_la_une.return_value = SelectedTopic(
                topic_id="c1",
                label="Breaking news",
                selection_reason="Traité par 2 sources",
                deep_angle="D",
                source_count=2,
            )
            mock_dependencies["curation"].select_topics.return_value = []
            mock_dependencies["deep"].match_for_topics.return_value = {"c1": None}
            mock_dependencies["actu"].match_global.side_effect = (
                lambda subjects, clusters, excluded_source_ids=None, excluded_content_ids=None: subjects
            )

            result = await svc.compute_global_context([article_a, article_b])

        assert result is not None
        subject = result.subjects[0]

        # Safety net: count reflects the 2 cluster outlets, not 0.
        assert subject.perspective_count == 2
        # No known bias → distribution all zero (spectrum bar hidden mobile-side).
        assert subject.bias_distribution == {
            "left": 0,
            "center-left": 0,
            "center": 0,
            "center-right": 0,
            "right": 0,
        }
        assert subject.bias_highlights is None
        # Stored snapshot must still carry the cluster outlets so
        # /contents/{id}/perspectives can return them instead of bailing
        # to the live path.
        assert subject.perspective_articles is not None
        assert len(subject.perspective_articles) == 2
        # Footer logos — one per outlet, matching the count.
        assert subject.perspective_sources is not None
        assert len(subject.perspective_sources) == 2
