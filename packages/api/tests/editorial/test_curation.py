"""Tests for CurationService (ÉTAPE 2 — LLM topic curation)."""

from dataclasses import dataclass, field
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import UUID, uuid4

import pytest

from app.services.editorial.config import EditorialConfig, FeatureFlags, PipelineConfig, PromptConfig
from app.services.editorial.curation import CurationService, THEME_DEEP_ANGLES, DEFAULT_DEEP_ANGLE
from app.services.editorial.schemas import SelectedTopic


def _make_cluster(
    cluster_id: str,
    label: str = "Test cluster",
    source_count: int = 3,
    theme: str | None = "politique",
    is_trending: bool = False,
):
    """Create a mock TopicCluster."""
    cluster = MagicMock()
    cluster.cluster_id = cluster_id
    cluster.label = label
    cluster.source_ids = set(uuid4() for _ in range(source_count))
    cluster.theme = theme
    cluster.is_trending = is_trending

    # Contents for ClusterSummary conversion
    content = MagicMock()
    content.title = f"Article about {label}"
    cluster.contents = [content]

    return cluster


def _make_config(**overrides) -> EditorialConfig:
    pipeline_kwargs = {"subjects_count": 5, "cluster_input_limit": 15}
    pipeline_kwargs.update(overrides)
    return EditorialConfig(
        pipeline=PipelineConfig(**pipeline_kwargs),
        curation_prompt=PromptConfig(system="Select {subjects_count} topics"),
    )


class TestSelectTopics:
    @pytest.mark.asyncio
    async def test_llm_valid_topics(self):
        clusters = [
            _make_cluster("c1", "Retraites", 6, "politique"),
            _make_cluster("c2", "Inflation", 4, "economie"),
            _make_cluster("c3", "Canicule", 3, "environnement"),
            _make_cluster("c4", "IA Europe", 5, "technologie"),
            _make_cluster("c5", "Logement", 4, "societe"),
            _make_cluster("c6", "Éducation", 3, "education"),
        ]

        llm = MagicMock()
        llm.is_ready = True
        llm.chat_json = AsyncMock(return_value={
            "topics": [
                {"topic_id": "c1", "label": "Retraites: vote décisif", "selection_reason": "Impact", "deep_angle": "Modèle social"},
                {"topic_id": "c4", "label": "Europe et IA", "selection_reason": "Tech", "deep_angle": "Souveraineté"},
                {"topic_id": "c3", "label": "Chaleur record", "selection_reason": "Climat", "deep_angle": "Réchauffement"},
                {"topic_id": "c5", "label": "Crise du logement", "selection_reason": "Social", "deep_angle": "Urbanisme"},
                {"topic_id": "c2", "label": "Hausse des prix", "selection_reason": "Économie", "deep_angle": "Inflation"},
            ]
        })

        svc = CurationService(llm, _make_config())
        result = await svc.select_topics(clusters)

        assert len(result) == 5
        assert all(isinstance(t, SelectedTopic) for t in result)
        assert result[0].topic_id == "c1"
        assert result[1].topic_id == "c4"

    @pytest.mark.asyncio
    async def test_llm_incomplete_fills_deterministic(self):
        clusters = [
            _make_cluster("c1", "Retraites", 6, "politique"),
            _make_cluster("c2", "Inflation", 4, "economie"),
            _make_cluster("c3", "Canicule", 3, "environnement"),
        ]

        llm = MagicMock()
        llm.is_ready = True
        # LLM returns only 2 topics instead of 3
        llm.chat_json = AsyncMock(return_value={
            "topics": [
                {"topic_id": "c1", "label": "Retraites", "selection_reason": "Impact", "deep_angle": "Social"},
                {"topic_id": "c3", "label": "Chaleur", "selection_reason": "Climat", "deep_angle": "Écologie"},
            ]
        })

        svc = CurationService(llm, _make_config(subjects_count=3))
        result = await svc.select_topics(clusters)

        assert len(result) == 3
        # Third should be filled from deterministic (c2 is the remaining)
        topic_ids = {t.topic_id for t in result}
        assert "c2" in topic_ids

    @pytest.mark.asyncio
    async def test_llm_invalid_response_fallback_deterministic(self):
        clusters = [
            _make_cluster("c1", "Retraites", 6, "politique"),
            _make_cluster("c2", "Inflation", 4, "economie"),
            _make_cluster("c3", "Canicule", 3, "environnement"),
        ]

        llm = MagicMock()
        llm.is_ready = True
        llm.chat_json = AsyncMock(return_value=None)  # LLM failed

        svc = CurationService(llm, _make_config(subjects_count=3))
        result = await svc.select_topics(clusters)

        assert len(result) == 3
        # Deterministic: sorted by source_count desc
        assert result[0].topic_id == "c1"  # 6 sources
        assert result[1].topic_id == "c2"  # 4 sources

    @pytest.mark.asyncio
    async def test_llm_not_ready_fallback(self):
        clusters = [
            _make_cluster("c1", "Retraites", 6, "politique"),
            _make_cluster("c2", "Inflation", 4, "economie"),
        ]

        llm = MagicMock()
        llm.is_ready = False

        svc = CurationService(llm, _make_config(subjects_count=2))
        result = await svc.select_topics(clusters)

        assert len(result) == 2
        # chat_json should not have been called
        llm.chat_json.assert_not_called()

    @pytest.mark.asyncio
    async def test_invalid_topic_id_filtered(self):
        clusters = [
            _make_cluster("c1", "Retraites", 6, "politique"),
            _make_cluster("c2", "Inflation", 4, "economie"),
            _make_cluster("c3", "Canicule", 3, "environnement"),
        ]

        llm = MagicMock()
        llm.is_ready = True
        llm.chat_json = AsyncMock(return_value={
            "topics": [
                {"topic_id": "INVALID", "label": "Bad", "selection_reason": "X", "deep_angle": "Y"},
                {"topic_id": "c1", "label": "OK", "selection_reason": "Good", "deep_angle": "Z"},
            ]
        })

        svc = CurationService(llm, _make_config(subjects_count=3))
        result = await svc.select_topics(clusters)

        assert len(result) == 3
        # c1 from LLM, 2 filled from deterministic
        assert result[0].topic_id == "c1"

    @pytest.mark.asyncio
    async def test_empty_clusters_returns_empty(self):
        llm = MagicMock()
        llm.is_ready = True

        svc = CurationService(llm, _make_config())
        result = await svc.select_topics([])
        assert result == []

    @pytest.mark.asyncio
    async def test_fewer_clusters_than_count(self):
        clusters = [_make_cluster("c1", "Solo", 5)]

        llm = MagicMock()
        llm.is_ready = False

        svc = CurationService(llm, _make_config())
        result = await svc.select_topics(clusters)

        assert len(result) == 1


class TestDeterministicSelect:
    def test_theme_diversity(self):
        clusters = [
            _make_cluster("c1", "Retraites", 6, "politique"),
            _make_cluster("c2", "Elections", 5, "politique"),  # Same theme
            _make_cluster("c3", "Inflation", 4, "economie"),
            _make_cluster("c4", "Canicule", 3, "environnement"),
        ]

        llm = MagicMock()
        svc = CurationService(llm, _make_config())
        result = svc._deterministic_select(clusters, 3)

        themes = [t.topic_id for t in result]
        # c1 (politique), c3 (economie), c4 (environnement) preferred for diversity
        assert "c1" in themes
        assert "c3" in themes
        assert "c4" in themes

    def test_deep_angle_from_theme(self):
        clusters = [_make_cluster("c1", "Test", 5, "sciences")]

        llm = MagicMock()
        svc = CurationService(llm, _make_config())
        result = svc._deterministic_select(clusters, 1)

        assert result[0].deep_angle == THEME_DEEP_ANGLES["sciences"]

    def test_unknown_theme_uses_default(self):
        clusters = [_make_cluster("c1", "Test", 5, "unknown_theme")]

        llm = MagicMock()
        svc = CurationService(llm, _make_config())
        result = svc._deterministic_select(clusters, 1)

        assert result[0].deep_angle == DEFAULT_DEEP_ANGLE

    def test_selection_reason_format(self):
        clusters = [_make_cluster("c1", "Test", 5)]

        llm = MagicMock()
        svc = CurationService(llm, _make_config())
        result = svc._deterministic_select(clusters, 1)

        assert "5 sources" in result[0].selection_reason
