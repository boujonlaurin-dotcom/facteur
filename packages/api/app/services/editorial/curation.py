"""ÉTAPE 2 — LLM topic curation.

Selects 3 topics from hot topic clusters using Claude.
Fallback: deterministic selection by source count.
"""

from __future__ import annotations

import json

import structlog

from app.services.briefing.importance_detector import TopicCluster
from app.services.editorial.config import EditorialConfig
from app.services.editorial.llm_client import EditorialLLMClient
from app.services.editorial.schemas import ClusterSummary, SelectedTopic

logger = structlog.get_logger()

# Heuristic deep angles per theme (used in deterministic fallback)
THEME_DEEP_ANGLES: dict[str, str] = {
    "politique": "Les dynamiques institutionnelles et democratiques sous-jacentes",
    "economie": "Les mecanismes structurels economiques en jeu",
    "societe": "Les transformations sociales de fond",
    "environnement": "Les enjeux ecologiques systemiques",
    "technologie": "L'impact structurel du numerique sur la societe",
    "international": "Les rapports de force geopolitiques",
    "culture": "Les evolutions culturelles de fond",
    "sciences": "Les implications scientifiques a long terme",
    "sante": "Les enjeux de sante publique structurels",
    "education": "Les transformations du systeme educatif",
}
DEFAULT_DEEP_ANGLE = "Les dynamiques structurelles et systemiques de ce sujet"


class CurationService:
    """Selects 3 editorial topics from topic clusters via LLM."""

    def __init__(self, llm: EditorialLLMClient, config: EditorialConfig) -> None:
        self._llm = llm
        self._config = config

    async def select_topics(
        self,
        clusters: list[TopicCluster],
        subjects_count: int | None = None,
    ) -> list[SelectedTopic]:
        """Select N topics from clusters using LLM curation.

        Args:
            clusters: All topic clusters, sorted by size desc.
            subjects_count: Override from config (default: 3).

        Returns:
            List of SelectedTopic. Falls back to deterministic if LLM fails.
        """
        count = subjects_count or self._config.pipeline.subjects_count
        limit = self._config.pipeline.cluster_input_limit

        # Take top clusters by source count
        top_clusters = sorted(clusters, key=lambda c: len(c.source_ids), reverse=True)[
            :limit
        ]

        if len(top_clusters) < count:
            logger.warning(
                "curation.insufficient_clusters",
                available=len(top_clusters),
                required=count,
            )
            # Use what we have
            count = min(count, len(top_clusters))

        if not top_clusters:
            return []

        # Try LLM curation
        if self._llm.is_ready:
            result = await self._llm_select(top_clusters, count)
            if result:
                return result

        # Fallback: deterministic selection
        logger.info("curation.fallback_deterministic")
        return self._deterministic_select(top_clusters, count)

    async def _llm_select(
        self,
        clusters: list[TopicCluster],
        count: int,
    ) -> list[SelectedTopic] | None:
        """LLM-based topic selection."""
        summaries = [self._cluster_to_summary(c) for c in clusters]
        user_message = json.dumps(
            [s.model_dump() for s in summaries], ensure_ascii=False, indent=2
        )

        prompt_cfg = self._config.curation_prompt
        system = prompt_cfg.system.format(subjects_count=count)

        raw = await self._llm.chat_json(
            system=system,
            user_message=user_message,
            model=prompt_cfg.model,
            temperature=prompt_cfg.temperature,
            max_tokens=prompt_cfg.max_tokens,
        )

        if not raw:
            logger.warning("curation.llm_empty_response")
            return None

        # Extract topics array — Mistral json_object returns {"topics": [...]}
        topics_list = raw
        if isinstance(raw, dict):
            topics_list = raw.get("topics", [])
        if not isinstance(topics_list, list):
            logger.warning("curation.llm_invalid_response", raw_type=type(raw).__name__)
            return None

        # Validate and parse
        valid_topic_ids = {c.cluster_id for c in clusters}
        selected: list[SelectedTopic] = []

        for item in topics_list[:count]:
            try:
                topic = SelectedTopic(**item)
                # Validate topic_id exists in our clusters
                if topic.topic_id not in valid_topic_ids:
                    logger.warning(
                        "curation.invalid_topic_id",
                        topic_id=topic.topic_id,
                        valid_ids=list(valid_topic_ids)[:5],
                    )
                    continue
                selected.append(topic)
            except Exception:
                logger.exception("curation.parse_topic_failed", item=str(item)[:200])
                continue

        if len(selected) < count:
            logger.warning(
                "curation.incomplete_selection",
                selected=len(selected),
                expected=count,
            )
            # Fill remaining with deterministic picks
            used_ids = {t.topic_id for t in selected}
            remaining = [c for c in clusters if c.cluster_id not in used_ids]
            for fill in self._deterministic_select(remaining, count - len(selected)):
                selected.append(fill)

        return selected[:count] if selected else None

    def _deterministic_select(
        self,
        clusters: list[TopicCluster],
        count: int,
    ) -> list[SelectedTopic]:
        """Fallback: pick top clusters by source diversity + theme diversity."""
        selected: list[SelectedTopic] = []
        used_themes: set[str | None] = set()

        # Sort by source_count desc
        sorted_clusters = sorted(
            clusters, key=lambda c: len(c.source_ids), reverse=True
        )

        for cluster in sorted_clusters:
            if len(selected) >= count:
                break

            # Prefer theme diversity (skip if same theme already picked, unless needed)
            if cluster.theme in used_themes and len(selected) < count - 1:
                continue

            deep_angle = THEME_DEEP_ANGLES.get(cluster.theme or "", DEFAULT_DEEP_ANGLE)
            selected.append(
                SelectedTopic(
                    topic_id=cluster.cluster_id,
                    label=cluster.label[:80],
                    selection_reason=f"Couvert par {len(cluster.source_ids)} sources",
                    deep_angle=deep_angle,
                )
            )
            used_themes.add(cluster.theme)

        # If diversity constraint was too strict, fill remaining
        if len(selected) < count:
            used_ids = {t.topic_id for t in selected}
            for cluster in sorted_clusters:
                if len(selected) >= count:
                    break
                if cluster.cluster_id in used_ids:
                    continue
                deep_angle = THEME_DEEP_ANGLES.get(
                    cluster.theme or "", DEFAULT_DEEP_ANGLE
                )
                selected.append(
                    SelectedTopic(
                        topic_id=cluster.cluster_id,
                        label=cluster.label[:80],
                        selection_reason=f"Couvert par {len(cluster.source_ids)} sources",
                        deep_angle=deep_angle,
                    )
                )

        return selected[:count]

    @staticmethod
    def _cluster_to_summary(cluster: TopicCluster) -> ClusterSummary:
        """Convert TopicCluster dataclass to serializable ClusterSummary."""
        return ClusterSummary(
            topic_id=cluster.cluster_id,
            label=cluster.label,
            article_titles=[c.title for c in cluster.contents[:10]],
            source_count=len(cluster.source_ids),
            is_trending=cluster.is_trending,
            theme=cluster.theme,
        )
