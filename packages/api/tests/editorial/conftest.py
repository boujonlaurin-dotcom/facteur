"""Fixtures partagées des tests du pipeline éditorial.

`mock_dependencies` vivait dans `test_pipeline.py` ; il est remonté ici depuis
que `test_pipeline_consensus.py` (Story 35.1) en a besoin lui aussi — un import
croisé entre deux modules de test redéfinit le fixture au lieu de le partager.
Les factories de mocks, elles, sont dans `factories.py` (un fixture se partage
par conftest, une fonction s'importe).
"""

from unittest.mock import AsyncMock, MagicMock, patch
from urllib.parse import urlparse

import pytest

from app.services.perspective_service import Perspective


@pytest.fixture
def mock_dependencies():
    """Patch all external dependencies of EditorialPipelineService.

    Note: DeepMatcher is disabled in the post-unification cleanup. The
    pipeline hardcodes ``deep_matches = {topic_id: None}`` so no patch is
    required for it.
    """
    with (
        patch("app.services.editorial.pipeline.load_editorial_config") as mock_config,
        patch("app.services.editorial.pipeline.EditorialLLMClient") as mock_llm_cls,
        patch("app.services.editorial.pipeline.CurationService") as mock_curation_cls,
        patch("app.services.editorial.pipeline.ActuMatcher") as mock_actu_cls,
        patch(
            "app.services.editorial.pipeline.PerspectiveService"
        ) as mock_perspective_cls,
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

        # Actu matcher
        mock_actu = MagicMock()
        mock_actu_cls.return_value = mock_actu

        # Perspective service
        mock_perspective = MagicMock()
        mock_perspective.get_perspectives_hybrid = AsyncMock(return_value=([], []))
        mock_perspective.resolve_bias = AsyncMock(return_value="center")
        mock_perspective.analyze_divergences = AsyncMock(return_value=None)
        # Story 35.1 : c'est `analyze_consensus` que le pipeline appelle
        # désormais à l'étape 3C. `analyze_divergences` reste mocké tant
        # que le routeur /perspectives/analyze s'en sert (PR 2).
        mock_perspective.analyze_consensus = AsyncMock(return_value=None)
        mock_perspective._extract_domain.side_effect = lambda url: urlparse(
            url
        ).netloc.removeprefix("www.")

        async def _build_coverage_universe(reference, contents, discovered):
            """Deterministic stand-in for the service's domain-level merge."""
            merged = []
            seen_domains = set()
            for content in contents:
                source = getattr(content, "source", None)
                source_url = getattr(source, "url", "") or ""
                domain = urlparse(source_url).netloc.removeprefix("www.")
                if not domain:
                    domain = urlparse(getattr(content, "url", "") or "").netloc
                    domain = domain.removeprefix("www.")
                if not domain or domain in seen_domains:
                    continue
                seen_domains.add(domain)
                bias = await mock_perspective.resolve_bias(
                    domain=domain,
                    source_name=getattr(source, "name", "") or domain,
                )
                merged.append(
                    Perspective(
                        title=content.title,
                        url=content.url,
                        source_name=getattr(source, "name", "") or domain,
                        source_domain=domain,
                        bias_stance=bias,
                        published_at=(
                            content.published_at.isoformat()
                            if content.published_at
                            else None
                        ),
                        description=getattr(content, "description", None),
                        language=getattr(content, "language", None),
                        content_id=str(content.id),
                    )
                )
            for perspective in discovered:
                domain = perspective.source_domain.removeprefix("www.")
                if not domain or domain in seen_domains:
                    continue
                perspective.source_domain = domain
                seen_domains.add(domain)
                merged.append(perspective)
            return merged

        async def _build_cluster_perspectives(contents):
            if not contents:
                return []
            return await _build_coverage_universe(contents[0], contents, [])

        mock_perspective.build_coverage_universe = AsyncMock(
            side_effect=_build_coverage_universe
        )
        mock_perspective.build_cluster_perspectives = AsyncMock(
            side_effect=_build_cluster_perspectives
        )
        mock_perspective_cls.return_value = mock_perspective

        yield {
            "config": config,
            "llm": mock_llm,
            "curation": mock_curation,
            "actu": mock_actu,
            "perspective": mock_perspective,
        }
