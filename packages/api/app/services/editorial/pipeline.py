"""Editorial digest pipeline orchestrator — Stories 10.23 + 10.24.

Orchestrates: clustering → LLM curation → deep matching → writing → pépite → coup de coeur.

Global phase (compute_global_context): 1x per batch, shared across users.
Per-user phase (run_for_user): actu matching only, no LLM.
"""

from __future__ import annotations

import asyncio
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
    CoupDeCoeurArticle,
    EditorialGlobalContext,
    EditorialPipelineResult,
    EditorialSubject,
    PepiteArticle,
    WritingOutput,
)
from app.services.editorial.writer import EditorialWriterService

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
        mode: str = "pour_vous",
    ) -> EditorialGlobalContext | None:
        """Compute global editorial context (1x per batch).

        This performs all LLM calls (curation + deep matching + writing + pépite)
        and 1 DB query (coup de coeur). Result is reused for all users.

        Args:
            contents: Recent articles for clustering (typically < 48h).
            mode: "pour_vous" or "serein" — affects writing prompt.

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

        # Build subjects with deep matches
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

        # ÉTAPE 3A: Actu matching GLOBAL (not per-user — MVP V2)
        # Collect deep source_ids to enforce source diversity within a subject
        deep_source_ids = {
            s.deep_article.source_id for s in subjects if s.deep_article is not None
        }
        step_start = time.time()
        subjects = self.actu_matcher.match_global(
            subjects=subjects,
            clusters=clusters,
            excluded_source_ids=deep_source_ids,
        )
        actu_time = time.time() - step_start
        actu_hit_count = sum(1 for s in subjects if s.actu_article is not None)
        logger.info(
            "editorial_pipeline.actu_matching_done",
            hits=actu_hit_count,
            total=len(subjects),
            duration_ms=round(actu_time * 1000, 2),
        )

        # Warn about subjects with no articles at all
        for s in subjects:
            if s.actu_article is None and s.deep_article is None:
                logger.warning(
                    "editorial_pipeline.subject_no_articles",
                    topic_id=s.topic_id,
                    label=s.label,
                )

        # Serialize cluster data (clusters are dataclasses)
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

        # ÉTAPES 4+5+6: Writing + Pépite + Coup de coeur (parallel)
        step_start = time.time()
        writer = EditorialWriterService(self.session, self.llm, self.config)

        selected_topic_ids = {s.topic_id for s in subjects}
        selected_content_ids: set[UUID] = set()
        for s in subjects:
            if s.deep_article:
                selected_content_ids.add(s.deep_article.content_id)

        writing_raw, pepite_raw, coup_de_coeur_raw = await asyncio.gather(
            writer.write_editorial(subjects, mode=mode),
            writer.select_pepite(contents, selected_topic_ids, cluster_data),
            writer.get_coup_de_coeur(selected_content_ids),
            return_exceptions=True,
        )

        # Handle writing result — inject texts into subjects
        writing_result: WritingOutput | None = None
        if isinstance(writing_raw, WritingOutput):
            writing_result = writing_raw
            topic_map = {sw.topic_id: sw for sw in writing_result.subjects}
            for i, s in enumerate(subjects):
                sw = topic_map.get(s.topic_id)
                if not sw and i < len(writing_result.subjects):
                    # Positional fallback: LLM may have modified the UUID
                    sw = writing_result.subjects[i]
                    logger.warning(
                        "editorial_pipeline.topic_id_mismatch_positional_fallback",
                        expected=s.topic_id,
                        got=writing_result.subjects[i].topic_id,
                    )
                if sw:
                    s.intro_text = sw.intro_text
                    s.transition_text = sw.transition_text
        elif isinstance(writing_raw, Exception):
            logger.error("editorial_pipeline.writing_exception", error=str(writing_raw))

        # Handle pépite
        pepite: PepiteArticle | None = None
        if isinstance(pepite_raw, PepiteArticle):
            pepite = pepite_raw
        elif isinstance(pepite_raw, Exception):
            logger.error("editorial_pipeline.pepite_exception", error=str(pepite_raw))

        # Handle coup de coeur
        coup_de_coeur: CoupDeCoeurArticle | None = None
        if isinstance(coup_de_coeur_raw, CoupDeCoeurArticle):
            coup_de_coeur = coup_de_coeur_raw
        elif isinstance(coup_de_coeur_raw, Exception):
            logger.error(
                "editorial_pipeline.coup_de_coeur_exception",
                error=str(coup_de_coeur_raw),
            )

        writing_time = time.time() - step_start
        logger.info(
            "editorial_pipeline.writing_done",
            has_writing=writing_result is not None,
            has_pepite=pepite is not None,
            has_coup_de_coeur=coup_de_coeur is not None,
            duration_ms=round(writing_time * 1000, 2),
        )

        total_time = time.time() - start
        logger.info(
            "editorial_pipeline.global_context_ready",
            subjects=len(subjects),
            deep_hits=deep_hit_count,
            has_editorial_text=writing_result is not None,
            total_ms=round(total_time * 1000, 2),
        )

        return EditorialGlobalContext(
            subjects=subjects,
            cluster_data=cluster_data,
            generated_at=datetime.now(UTC),
            header_text=writing_result.header_text if writing_result else None,
            closure_text=writing_result.closure_text if writing_result else None,
            cta_text=writing_result.cta_text if writing_result else None,
            pepite=pepite,
            coup_de_coeur=coup_de_coeur,
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
            header_text=global_ctx.header_text,
            closure_text=global_ctx.closure_text,
            cta_text=global_ctx.cta_text,
            pepite=global_ctx.pepite,
            coup_de_coeur=global_ctx.coup_de_coeur,
        )

    async def close(self) -> None:
        """Cleanup resources."""
        await self.llm.close()
