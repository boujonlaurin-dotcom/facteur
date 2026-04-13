"""Regression tests — serein filter + low-priority cap in the editorial pipeline.

Covers the fix for `bug-digest-serein-collision-2026-04-13`:
- Serein mode drops clusters flagged as non-serein-compatible BEFORE the
  curation step, so the serein digest no longer reuses the normal-mode
  articles when anxious topics dominate the pool.
- Both modes cap sport + faits divers clusters at 1 each (with a safety
  escape hatch when the remaining pool is too small).
"""

from unittest.mock import AsyncMock, MagicMock, patch
from uuid import UUID, uuid4

import pytest

from app.services.editorial.schemas import SelectedTopic


def _make_content(title="x", description=""):
    c = MagicMock()
    c.id = uuid4()
    c.title = title
    c.description = description
    c.source_id = uuid4()
    c.source = MagicMock()
    c.source.name = "S"
    c.entities = None
    return c


def _make_cluster(cid, titles, theme=None, source_count=3):
    cluster = MagicMock()
    cluster.cluster_id = cid
    cluster.label = cid
    cluster.contents = [_make_content(title=t) for t in titles]
    cluster.source_ids = {uuid4() for _ in range(source_count)}
    cluster.theme = theme
    cluster.is_trending = source_count >= 3
    return cluster


@pytest.fixture
def mock_deps():
    with (
        patch("app.services.editorial.pipeline.load_editorial_config") as mock_config,
        patch("app.services.editorial.pipeline.EditorialLLMClient") as mock_llm_cls,
        patch("app.services.editorial.pipeline.CurationService") as mock_curation_cls,
        patch("app.services.editorial.pipeline.DeepMatcher") as mock_deep_cls,
        patch("app.services.editorial.pipeline.ActuMatcher") as mock_actu_cls,
        patch(
            "app.services.editorial.pipeline.PerspectiveService"
        ) as mock_perspective_cls,
    ):
        from app.services.editorial.config import EditorialConfig, PipelineConfig

        mock_config.return_value = EditorialConfig(pipeline=PipelineConfig())

        mock_llm = MagicMock()
        mock_llm.is_ready = True
        mock_llm.close = AsyncMock()
        mock_llm_cls.return_value = mock_llm

        mock_curation = MagicMock()
        mock_curation.select_topics = AsyncMock(return_value=[])
        mock_curation.select_a_la_une = AsyncMock(return_value=None)
        mock_curation.select_bonne_nouvelle = AsyncMock(return_value=None)
        mock_curation_cls.return_value = mock_curation

        mock_deep = MagicMock()
        mock_deep.match_for_topics = AsyncMock(return_value={})
        mock_deep_cls.return_value = mock_deep

        mock_actu = MagicMock()
        mock_actu.match_global.side_effect = (
            lambda subjects, clusters, excluded_source_ids=None, excluded_content_ids=None: subjects
        )
        mock_actu_cls.return_value = mock_actu

        mock_perspective = MagicMock()
        mock_perspective.get_perspectives_hybrid = AsyncMock(return_value=([], []))
        mock_perspective.resolve_bias = AsyncMock(return_value="center")
        mock_perspective.analyze_divergences = AsyncMock(return_value=None)
        mock_perspective_cls.return_value = mock_perspective

        yield {
            "llm": mock_llm,
            "curation": mock_curation,
            "deep": mock_deep,
            "actu": mock_actu,
            "perspective": mock_perspective,
        }


class TestSereinClusterFilter:
    """compute_global_context(mode='serein') drops anxious clusters."""

    @pytest.mark.asyncio
    async def test_serein_excludes_anxious_clusters(self, mock_deps):
        from app.services.editorial.pipeline import EditorialPipelineService

        # 3 anxious, 3 neutral; only neutrals should reach the curation step
        clusters = [
            _make_cluster(
                "war", ["Guerre en Ukraine : bombardements"], theme="international"
            ),
            _make_cluster(
                "pol", ["Macron annonce réforme"], theme="politics"
            ),
            _make_cluster(
                "crime", ["Meurtre à Paris", "Agression dans le métro"], theme=None
            ),
            _make_cluster("sci", ["Découverte scientifique"], theme="science"),
            _make_cluster("cult", ["Festival de Cannes"], theme="culture"),
            _make_cluster("tech", ["Innovation robotique"], theme="technology"),
        ]

        captured_ids: list[str] = []

        async def _capture_select_topics(
            available, subjects_count=None, excluded_cluster_ids=None
        ):
            for c in available:
                captured_ids.append(c.cluster_id)
            return []

        mock_deps["curation"].select_topics.side_effect = _capture_select_topics

        svc = EditorialPipelineService(AsyncMock())
        with patch(
            "app.services.editorial.pipeline.ImportanceDetector"
        ) as mock_detector_cls:
            mock_detector = MagicMock()
            mock_detector.build_topic_clusters.return_value = clusters
            mock_detector_cls.return_value = mock_detector
            await svc.compute_global_context(
                [_make_content("x") for _ in range(5)], mode="serein"
            )

        # Curation must have been called on only non-anxious clusters
        assert "war" not in captured_ids
        assert "pol" not in captured_ids
        assert "crime" not in captured_ids
        # At least one neutral cluster must have been offered to the curator
        assert any(c in captured_ids for c in ("sci", "cult", "tech"))

    @pytest.mark.asyncio
    async def test_pour_vous_keeps_anxious_clusters(self, mock_deps):
        """Sanity check: pour_vous is NOT filtered by the serein rule."""
        from app.services.editorial.pipeline import EditorialPipelineService

        clusters = [
            _make_cluster("war", ["Guerre en Ukraine"], theme="international"),
            _make_cluster("pol", ["Macron réforme"], theme="politics"),
            _make_cluster("sci", ["Découverte"], theme="science"),
            _make_cluster("cult", ["Festival"], theme="culture"),
            _make_cluster("tech", ["Robotique"], theme="technology"),
        ]

        captured_ids: list[str] = []

        async def _capture_select_topics(
            available, subjects_count=None, excluded_cluster_ids=None
        ):
            for c in available:
                captured_ids.append(c.cluster_id)
            return []

        mock_deps["curation"].select_topics.side_effect = _capture_select_topics

        svc = EditorialPipelineService(AsyncMock())
        with patch(
            "app.services.editorial.pipeline.ImportanceDetector"
        ) as mock_detector_cls:
            mock_detector = MagicMock()
            mock_detector.build_topic_clusters.return_value = clusters
            mock_detector_cls.return_value = mock_detector
            await svc.compute_global_context(
                [_make_content("x") for _ in range(5)], mode="pour_vous"
            )

        # Anxious clusters must still be available to the curator in pour_vous
        assert "war" in captured_ids
        assert "pol" in captured_ids


class TestLowPrioritySportCap:
    """Sport clusters are capped at 1 across both modes."""

    @pytest.mark.asyncio
    async def test_multiple_sport_clusters_capped(self, mock_deps):
        from app.services.editorial.pipeline import EditorialPipelineService

        # 3 sport clusters + enough non-sport clusters so the cap is applied
        # (cap is skipped when it would leave < 5 clusters for curation).
        clusters = [
            _make_cluster("sport1", ["PSG OM"], theme="sport", source_count=5),
            _make_cluster("sport2", ["Tennis Roland-Garros"], theme="sport"),
            _make_cluster("sport3", ["Rugby France Angleterre"], theme="sport"),
            _make_cluster("pol", ["Élections"], theme="politics", source_count=4),
            _make_cluster("eco", ["Inflation"], theme="economy", source_count=4),
            _make_cluster("sci", ["Recherche"], theme="science", source_count=3),
            _make_cluster("tech", ["IA avancée"], theme="technology", source_count=3),
            _make_cluster("cult", ["Cinéma"], theme="culture", source_count=3),
        ]

        captured_ids: list[str] = []

        async def _capture_select_topics(
            available, subjects_count=None, excluded_cluster_ids=None
        ):
            for c in available:
                captured_ids.append(c.cluster_id)
            return []

        mock_deps["curation"].select_topics.side_effect = _capture_select_topics

        svc = EditorialPipelineService(AsyncMock())
        with patch(
            "app.services.editorial.pipeline.ImportanceDetector"
        ) as mock_detector_cls:
            mock_detector = MagicMock()
            mock_detector.build_topic_clusters.return_value = clusters
            mock_detector_cls.return_value = mock_detector
            await svc.compute_global_context(
                [_make_content("x") for _ in range(5)], mode="pour_vous"
            )

        sport_kept = [c for c in captured_ids if c.startswith("sport")]
        assert len(sport_kept) == 1, f"expected 1 sport cluster, got {sport_kept}"
        assert "sport1" in sport_kept  # largest kept

    @pytest.mark.asyncio
    async def test_cap_skipped_when_remaining_pool_too_small(self, mock_deps):
        """When dropping low-priority clusters would leave < 5, we keep them."""
        from app.services.editorial.pipeline import EditorialPipelineService

        # Pool is mostly sport — cap would reduce to 2 clusters, so skip cap
        clusters = [
            _make_cluster("sport1", ["PSG"], theme="sport", source_count=5),
            _make_cluster("sport2", ["Tennis"], theme="sport"),
            _make_cluster("sport3", ["Rugby"], theme="sport"),
            _make_cluster("sport4", ["Basket"], theme="sport"),
            _make_cluster("pol", ["Élections"], theme="politics"),
        ]

        captured_ids: list[str] = []

        async def _capture_select_topics(
            available, subjects_count=None, excluded_cluster_ids=None
        ):
            for c in available:
                captured_ids.append(c.cluster_id)
            return []

        mock_deps["curation"].select_topics.side_effect = _capture_select_topics

        svc = EditorialPipelineService(AsyncMock())
        with patch(
            "app.services.editorial.pipeline.ImportanceDetector"
        ) as mock_detector_cls:
            mock_detector = MagicMock()
            mock_detector.build_topic_clusters.return_value = clusters
            mock_detector_cls.return_value = mock_detector
            await svc.compute_global_context(
                [_make_content("x") for _ in range(5)], mode="pour_vous"
            )

        sport_kept = [c for c in captured_ids if c.startswith("sport")]
        # Cap skipped because pruning would leave < 5 clusters
        assert len(sport_kept) >= 2
