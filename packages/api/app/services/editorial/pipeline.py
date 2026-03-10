"""Editorial digest pipeline orchestrator — Story 10.23.

Orchestrates: clustering → LLM curation → actu matching → deep matching.

Global phase (compute_global_context): 1x per batch, shared across users.
Per-user phase (run_for_user): actu matching only, no LLM.
"""

from __future__ import annotations

import time
from datetime import UTC, datetime
from uuid import UUID

import structlog
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content import Content
from app.services.briefing.importance_detector import ImportanceDetector, TopicCluster
from app.services.editorial.actu_matcher import ActuMatcher
from app.services.editorial.config import load_editorial_config
from app.services.editorial.curation import CurationService
from app.services.editorial.deep_matcher import DeepMatcher
from app.services.editorial.llm_client import EditorialLLMClient
from app.services.editorial.schemas import (
    EditorialGlobalContext,
    EditorialPipelineResult,
    EditorialSubject,
)

logger = structlog.get_logger()


class EditorialPipelineService:
    """Orchestrates the editorial digest pipeline."""

    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.config = load_editorial_config()
        self.llm = EditorialLLMClient()
        self.curation = CurationService(self.llm, self.config)
        self.actu_matcher = ActuMatcher(
            actu_max_age_hours=self.config.pipeline.actu_max_age_hours
        )
        self.deep_matcher = DeepMatcher(session, self.llm, self.config)

    def is_enabled_for_user(self, user_id: str) -> bool:
        """Check if editorial pipeline is enabled for a user."""
        return self.config.is_enabled_for_user(user_id) and self.llm.is_ready

    async def compute_global_context(
        self,
        contents: list[Content],
    ) -> EditorialGlobalContext | None:
        """Compute global editorial context (1x per batch).

        This performs all LLM calls (curation + deep matching).
        The result is reused for all users — only actu matching is per-user.

        Args:
            contents: Recent articles for clustering (typically < 48h).

        Returns:
            EditorialGlobalContext or None if pipeline fails.
        """
        start = time.time()

        # ÉTAPE 1: Build topic clusters (reuse existing)
        detector = ImportanceDetector()
        clusters = detector.build_topic_clusters(contents)
        cluster_time = time.time() - start

        if not clusters:
            logger.warning("editorial_pipeline.no_clusters")
            return None

        logger.info(
            "editorial_pipeline.clusters_built",
            count=len(clusters),
            duration_ms=round(cluster_time * 1000, 2),
        )

        # ÉTAPE 2: LLM curation — select 3 topics
        step_start = time.time()
        selected_topics = await self.curation.select_topics(clusters)
        curation_time = time.time() - step_start

        if not selected_topics:
            logger.error("editorial_pipeline.curation_failed")
            return None

        logger.info(
            "editorial_pipeline.curation_done",
            topics=[t.topic_id for t in selected_topics],
            duration_ms=round(curation_time * 1000, 2),
        )

        # ÉTAPE 3B: Deep matching (global — same deep articles for all users)
        step_start = time.time()
        deep_matches = await self.deep_matcher.match_for_topics(selected_topics)
        deep_time = time.time() - step_start

        deep_hit_count = sum(1 for v in deep_matches.values() if v is not None)
        logger.info(
            "editorial_pipeline.deep_matching_done",
            hits=deep_hit_count,
            total=len(selected_topics),
            duration_ms=round(deep_time * 1000, 2),
        )

        # Build subjects with deep matches (actu will be filled per-user)
        subjects = [
            EditorialSubject(
                rank=i + 1,
                topic_id=topic.topic_id,
                label=topic.label,
                selection_reason=topic.selection_reason,
                deep_angle=topic.deep_angle,
                deep_article=deep_matches.get(topic.topic_id),
            )
            for i, topic in enumerate(selected_topics)
        ]

        # Serialize cluster data for actu matching (clusters are dataclasses)
        cluster_data = [
            {
                "cluster_id": c.cluster_id,
                "label": c.label,
                "content_ids": [str(content.id) for content in c.contents],
                "source_ids": [str(sid) for sid in c.source_ids],
                "theme": c.theme,
            }
            for c in clusters
        ]

        total_time = time.time() - start
        logger.info(
            "editorial_pipeline.global_context_ready",
            subjects=len(subjects),
            deep_hits=deep_hit_count,
            total_ms=round(total_time * 1000, 2),
        )

        return EditorialGlobalContext(
            subjects=subjects,
            cluster_data=cluster_data,
            generated_at=datetime.now(UTC),
        )

    def run_for_user(
        self,
        global_ctx: EditorialGlobalContext,
        clusters: list[TopicCluster],
        user_source_ids: set[UUID],
        excluded_content_ids: set[UUID],
    ) -> EditorialPipelineResult:
        """Per-user phase: match actu articles from user's sources.

        This is synchronous (no async needed) — pure in-memory matching.

        Args:
            global_ctx: Pre-computed global context.
            clusters: TopicCluster objects (with Content loaded).
            user_source_ids: User's followed source UUIDs.
            excluded_content_ids: Already-seen/dismissed content UUIDs.

        Returns:
            EditorialPipelineResult with subjects populated.
        """
        start = time.time()

        subjects = self.actu_matcher.match_for_user(
            subjects=global_ctx.subjects,
            clusters=clusters,
            user_source_ids=user_source_ids,
            excluded_content_ids=excluded_content_ids,
        )

        actu_hits = sum(1 for s in subjects if s.actu_article is not None)
        deep_hits = sum(1 for s in subjects if s.deep_article is not None)
        total_time = time.time() - start

        return EditorialPipelineResult(
            subjects=subjects,
            metadata={
                "actu_hits": actu_hits,
                "deep_hits": deep_hits,
                "total_subjects": len(subjects),
                "matching_ms": round(total_time * 1000, 2),
            },
        )

    async def close(self) -> None:
        """Cleanup resources."""
        await self.llm.close()
