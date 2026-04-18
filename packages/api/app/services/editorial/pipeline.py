"""Editorial digest pipeline orchestrator — Stories 10.23 + 10.24.

Orchestrates: clustering → LLM curation → deep matching → writing → pépite → coup de coeur.

Global phase (compute_global_context): 1x per batch, shared across users.
Per-user phase (run_for_user): actu matching only, no LLM.
"""

from __future__ import annotations

import asyncio
import time
from contextlib import asynccontextmanager
from datetime import UTC, datetime
from urllib.parse import urlparse
from uuid import UUID

import structlog
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.models.content import Content
from app.models.source import Source
from app.services.briefing.importance_detector import ImportanceDetector, TopicCluster
from app.services.editorial.actu_matcher import ActuMatcher
from app.services.editorial.config import load_editorial_config
from app.services.editorial.curation import CurationService, _cluster_to_une_topic
from app.services.editorial.deep_matcher import DeepMatcher
from app.services.editorial.llm_client import EditorialLLMClient
from app.services.editorial.schemas import (
    ActuDecaleeArticle,
    CoupDeCoeurArticle,
    EditorialGlobalContext,
    EditorialPipelineResult,
    EditorialSubject,
    PepiteArticle,
    PerspectiveSourceMini,
    WritingOutput,
    compute_bias_distribution,
    compute_bias_highlights,
    compute_divergence_level,
)
from app.services.editorial.writer import EditorialWriterService
from app.services.perspective_service import Perspective, PerspectiveService

logger = structlog.get_logger()


class EditorialPipelineService:
    """Orchestrates the editorial digest pipeline."""

    def __init__(
        self,
        session: AsyncSession,
        session_maker: async_sessionmaker[AsyncSession] | None = None,
    ) -> None:
        # `session_maker` est la voie préférée : chaque requête DB s'exécute
        # dans une session courte au lieu de tenir `self.session` ouverte
        # pendant 3-5 min de pipeline LLM. Cf. bug-infinite-load-requests.md
        # (site B, P1). `session` reste pour compat ascendante.
        self.session = session
        self.session_maker = session_maker
        self.config = load_editorial_config()
        self.llm = EditorialLLMClient()
        self.curation = CurationService(self.llm, self.config)
        self.actu_matcher = ActuMatcher(
            actu_max_age_hours=self.config.pipeline.actu_max_age_hours
        )
        self.deep_matcher = DeepMatcher(
            session, self.llm, self.config, session_maker=session_maker
        )

    @asynccontextmanager
    async def _short_session(self):
        """Open a short-lived session, or fall back to the injected one."""
        if self.session_maker is None:
            yield self.session
            return
        async with self.session_maker() as session:
            try:
                yield session
            except Exception:
                await session.rollback()
                raise

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

        # ÉTAPE 1A-bis: Mode-aware cluster filtering.
        # 1) Serein — drop clusters flagged anxious (defence-in-depth on top
        #    of the SQL-level apply_serein_filter already applied upstream).
        # 2) Both modes — cap faits divers + sport to at most 1 cluster each
        #    so the digest isn't dominated by these lower-priority topics.
        from app.services.recommendation.filter_presets import (
            cap_low_priority_clusters,
            is_cluster_serein_compatible,
        )

        pre_filter_count = len(clusters)
        if mode == "serein":
            clusters = [c for c in clusters if is_cluster_serein_compatible(c)]
            logger.info(
                "editorial_pipeline.serein_cluster_filter",
                before=pre_filter_count,
                after=len(clusters),
            )
            if not clusters:
                logger.warning("editorial_pipeline.serein_no_compatible_clusters")
                return None

        # Cap low-priority clusters (sport + faits divers) — applies to both
        # modes. Clusters are sorted by size desc so the largest — typically
        # the most trending — is kept. Skip the cap if the remaining non-
        # low-priority pool would be too small to pick 5 subjects.
        sorted_by_size = sorted(clusters, key=lambda c: len(c.source_ids), reverse=True)
        capped = cap_low_priority_clusters(sorted_by_size)
        if len(capped) >= 5:
            dropped = len(sorted_by_size) - len(capped)
            clusters = capped
            logger.info(
                "editorial_pipeline.low_priority_cap_applied",
                mode=mode,
                dropped=dropped,
                remaining=len(clusters),
            )
        else:
            logger.info(
                "editorial_pipeline.low_priority_cap_skipped",
                mode=mode,
                reason="insufficient_non_low_priority_pool",
                capped_size=len(capped),
            )

        # ÉTAPE 1B: Pré-sélection "À la Une" — cluster le plus couvert
        step_start = time.time()
        trending_clusters = [c for c in clusters if c.is_trending]
        a_la_une_topic = None

        if trending_clusters:
            top3 = sorted(
                trending_clusters, key=lambda c: len(c.source_ids), reverse=True
            )[:3]

            if len(top3) == 1:
                a_la_une_topic = _cluster_to_une_topic(top3[0])
            elif mode == "serein":
                a_la_une_topic = await self.curation.select_bonne_nouvelle(top3)
                if not a_la_une_topic:
                    a_la_une_topic = _cluster_to_une_topic(top3[0])
            else:
                a_la_une_topic = await self.curation.select_a_la_une(top3)
                if not a_la_une_topic:
                    a_la_une_topic = _cluster_to_une_topic(top3[0])

            logger.info(
                "editorial_pipeline.a_la_une_selected",
                topic_id=a_la_une_topic.topic_id,
                source_count=a_la_une_topic.source_count,
                label=a_la_une_topic.label,
            )

        une_time = time.time() - step_start

        # ÉTAPE 2: LLM curation — select remaining topics
        step_start = time.time()
        excluded_ids = {a_la_une_topic.topic_id} if a_la_une_topic else set()
        remaining_count = 4 if a_la_une_topic else 5
        selected_topics = await self.curation.select_topics(
            clusters,
            subjects_count=remaining_count,
            excluded_cluster_ids=excluded_ids,
        )

        # Assemble: À la Une in rank 1 + others in rank 2-3
        if a_la_une_topic:
            selected_topics = [a_la_une_topic] + selected_topics

        curation_time = time.time() - step_start + une_time

        if not selected_topics:
            logger.error("editorial_pipeline.curation_failed")
            return None

        logger.info(
            "editorial_pipeline.curation_done",
            topics=[t.topic_id for t in selected_topics],
            has_a_la_une=a_la_une_topic is not None,
            duration_ms=round(curation_time * 1000, 2),
        )

        # ÉTAPE 3B: Deep matching (global — same deep articles for all users)
        # Extract entities from clusters to boost deep matching accuracy
        cluster_map = {c.cluster_id: c for c in clusters}
        cluster_entities: dict[str, set[str]] = {}
        for topic in selected_topics:
            cluster = cluster_map.get(topic.topic_id)
            if cluster:
                entities: set[str] = set()
                for content in cluster.contents:
                    if content.entities:
                        for e in content.entities:
                            if e and ":" in e:
                                entities.add(e.split(":")[0].lower().strip())
                if entities:
                    cluster_entities[topic.topic_id] = entities

        step_start = time.time()
        deep_matches = await self.deep_matcher.match_for_topics(
            selected_topics, cluster_entities=cluster_entities
        )
        deep_time = time.time() - step_start

        deep_hit_count = sum(1 for v in deep_matches.values() if v is not None)
        logger.info(
            "editorial_pipeline.deep_matching_done",
            hits=deep_hit_count,
            total=len(selected_topics),
            duration_ms=round(deep_time * 1000, 2),
        )

        # Build subjects with deep matches
        cluster_map_counts = {c.cluster_id: len(c.source_ids) for c in clusters}
        subjects = [
            EditorialSubject(
                rank=i + 1,
                topic_id=topic.topic_id,
                label=topic.label,
                selection_reason=topic.selection_reason,
                deep_angle=topic.deep_angle,
                deep_article=deep_matches.get(topic.topic_id),
                source_count=topic.source_count
                or cluster_map_counts.get(topic.topic_id, 0),
                theme=topic.theme,
                is_a_la_une=(i == 0 and a_la_une_topic is not None),
            )
            for i, topic in enumerate(selected_topics)
        ]

        # ÉTAPE 3A: Actu matching GLOBAL (not per-user — MVP V2)
        # Collect deep source_ids AND content_ids to prevent actu/deep overlap
        deep_source_ids = {
            s.deep_article.source_id for s in subjects if s.deep_article is not None
        }
        deep_content_ids = {
            s.deep_article.content_id for s in subjects if s.deep_article is not None
        }
        step_start = time.time()
        subjects = self.actu_matcher.match_global(
            subjects=subjects,
            clusters=clusters,
            excluded_source_ids=deep_source_ids,
            excluded_content_ids=deep_content_ids,
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

        # ÉTAPE 3C: Perspective analysis (batch, parallel)
        # Pass session_maker: chaque resolve_bias / search_internal s'exécute
        # dans sa propre session courte, évitant 6-10 parallel DB calls sur
        # la même session tenue pendant la phase perspectives (~30s).
        perspective_service = PerspectiveService(
            db=self.session, session_maker=self.session_maker
        )
        step_start = time.time()

        async def _process_perspectives(
            subject: EditorialSubject,
            cluster: TopicCluster | None,
        ) -> None:
            """Enrich one subject with perspective data. Fallback on error.

            The cluster (articles ingested in our DB within the last 24-48h)
            is the source of truth for "how many media cover this topic". We:
              1. Build cluster-based perspectives — one per unique source.
              2. Augment with Google News for NEW domains only.
              3. Compute perspective_count / bias_distribution on the merged
                 list (filtered on known bias), so `sum(bias_distribution)
                 == perspective_count` while the count includes our own
                 curated sources — not just Google News.
            This aligns the carousel source_count with the Analyse de biais
            header and ensures the LLM divergence analysis talks about the
            same media set.
            """
            if not cluster or not cluster.contents:
                return

            representative = sorted(
                cluster.contents, key=lambda c: c.published_at, reverse=True
            )[0]

            # Step 1 — cluster-based perspectives (source of truth).
            # Helper is shared with /contents/{id}/perspectives so the
            # endpoint returns the same merged count as this pipeline (the
            # PR #390 invariant still holds between header and bottom sheet).
            ordered_contents = sorted(
                cluster.contents, key=lambda c: c.published_at, reverse=True
            )
            try:
                cluster_perspectives = (
                    await perspective_service.build_cluster_perspectives(
                        ordered_contents
                    )
                )
            except Exception:
                logger.warning(
                    "editorial_pipeline.cluster_perspectives_failed",
                    topic_id=subject.topic_id,
                )
                cluster_perspectives = []

            cluster_domains = {
                p.source_domain for p in cluster_perspectives if p.source_domain
            }

            # Step 2 — Google News augmentation (new domains only)
            exclude_domain = None
            if representative.source and representative.source.url:
                try:
                    parsed = urlparse(representative.source.url)
                    exclude_domain = parsed.netloc
                    if exclude_domain and exclude_domain.startswith("www."):
                        exclude_domain = exclude_domain[4:]
                except Exception:
                    pass

            try:
                gnews_perspectives, _ = (
                    await perspective_service.get_perspectives_hybrid(
                        content=representative,
                        exclude_domain=exclude_domain,
                    )
                )
            except Exception:
                logger.warning(
                    "editorial_pipeline.perspectives_fallback",
                    topic_id=subject.topic_id,
                )
                gnews_perspectives = []

            # Keep only Google News perspectives whose domain is not already
            # covered by the cluster — no double-counting.
            new_gnews = [
                p
                for p in gnews_perspectives
                if p.source_domain and p.source_domain not in cluster_domains
            ]

            merged_perspectives: list[Perspective] = cluster_perspectives + new_gnews

            # Pivot stable: propagate representative id so the mobile bottom sheet
            # re-fetches /perspectives on the SAME content as the one used here.
            subject.representative_content_id = representative.id

            # Single source of truth for the 3 UI counters (header, spectrum bar,
            # bottom sheet): exclude perspectives without a known bias_stance.
            # The bottom sheet endpoint (routers/contents.py) applies the same
            # filter, so the invariant `sum(bias_distribution) == perspective_count`
            # holds. The new twist vs. PR #390: the merged pool includes the
            # cluster's own sources, so the count actually reflects what users
            # see in the carousel.
            known_perspectives = [
                p for p in merged_perspectives if p.bias_stance != "unknown"
            ]
            subject.perspective_count = len(known_perspectives)
            subject.bias_distribution = compute_bias_distribution(known_perspectives)
            subject.bias_highlights = compute_bias_highlights(subject.bias_distribution)

            # Axe C — observability: log the composition so we can verify in
            # prod that the cluster count, perspective count and LLM analysis
            # describe the same media set.
            logger.info(
                "editorial_pipeline.perspectives_composition",
                topic_id=subject.topic_id,
                cluster_sources=len(cluster_perspectives),
                gnews_added=len(new_gnews),
                total_merged=len(merged_perspectives),
                known_bias=len(known_perspectives),
                unknown_bias=len(merged_perspectives) - len(known_perspectives),
            )

            # Build perspective_sources — max 6, deduplicated by domain.
            # Use known_perspectives so the CTA logos match the bottom sheet
            # (which also filters out unknown bias).
            seen_domains: set[str] = set()
            unique_perspectives = []
            for p in known_perspectives:
                if p.source_domain not in seen_domains:
                    seen_domains.add(p.source_domain)
                    unique_perspectives.append(p)
                if len(unique_perspectives) >= 6:
                    break

            # Best-effort logo resolution from DB. Skip perspectives with
            # empty source_domain: the ILIKE "%%" pattern would match every
            # row in the sources table.
            logo_map: dict[str, str] = {}
            perspectives_with_domain = [
                p for p in unique_perspectives if p.source_domain
            ]
            if perspectives_with_domain:
                try:
                    domain_patterns = [
                        f"%{p.source_domain}%" for p in perspectives_with_domain
                    ]
                    stmt = select(Source.url, Source.logo_url).where(
                        or_(
                            *[Source.url.ilike(pattern) for pattern in domain_patterns]
                        ),
                        Source.logo_url.is_not(None),
                    )
                    async with self._short_session() as session:
                        result = await session.execute(stmt)
                        logo_rows = list(result.all())
                    for row in logo_rows:
                        try:
                            parsed = urlparse(row.url)
                            domain = parsed.netloc
                            if domain.startswith("www."):
                                domain = domain[4:]
                            if domain and domain not in logo_map:
                                logo_map[domain] = row.logo_url
                        except Exception:
                            pass
                except Exception:
                    logger.warning(
                        "editorial_pipeline.logo_resolution_failed",
                        topic_id=subject.topic_id,
                    )

            subject.perspective_sources = [
                PerspectiveSourceMini(
                    name=p.source_name,
                    domain=p.source_domain,
                    bias_stance=p.bias_stance,
                    logo_url=logo_map.get(p.source_domain),
                ).model_dump(mode="json")
                for p in unique_perspectives
            ]

            # The LLM divergence analysis must describe the SAME media set
            # as the counters above — feed it the merged list (cluster +
            # Google News), not just Google News.
            if len(merged_perspectives) >= 3:
                try:
                    source_bias = await perspective_service.resolve_bias(
                        domain=exclude_domain or "",
                        source_name=(
                            representative.source.name if representative.source else ""
                        ),
                    )
                    divergence_result = await perspective_service.analyze_divergences(
                        article_title=representative.title,
                        source_name=(
                            representative.source.name if representative.source else ""
                        ),
                        source_bias=source_bias,
                        perspectives=[
                            {
                                "title": p.title,
                                "url": p.url,
                                "source_name": p.source_name,
                                "source_domain": p.source_domain,
                                "bias_stance": p.bias_stance,
                                "published_at": p.published_at,
                                "description": p.description,
                            }
                            for p in merged_perspectives
                        ],
                        article_description=representative.description,
                    )
                    if isinstance(divergence_result, dict):
                        analysis_raw = divergence_result.get("analysis")
                        # Round 3 fix (Sentry PYTHON-R) : le LLM peut renvoyer
                        # un dict imbriqué (ex: {"contexte": "...", "liens": [...]})
                        # au lieu d'une string plate. Pydantic rejette → 500 sur
                        # /digest/both. Coerce en string propre ici, source du bug.
                        if isinstance(analysis_raw, dict):
                            import json as _json

                            subject.divergence_analysis = _json.dumps(
                                analysis_raw, ensure_ascii=False
                            )
                        elif analysis_raw is not None and not isinstance(
                            analysis_raw, str
                        ):
                            subject.divergence_analysis = str(analysis_raw)
                        else:
                            subject.divergence_analysis = analysis_raw
                        subject.divergence_level = divergence_result.get(
                            "divergence_level"
                        )
                    elif isinstance(divergence_result, str):
                        subject.divergence_analysis = divergence_result
                except Exception:
                    logger.warning(
                        "editorial_pipeline.divergence_analysis_failed",
                        topic_id=subject.topic_id,
                    )
                    subject.divergence_analysis = None

            # Fallback: derive divergence_level from stats if LLM didn't provide it
            if subject.divergence_level is None and subject.bias_distribution:
                subject.divergence_level = compute_divergence_level(
                    subject.bias_distribution
                )

        await asyncio.gather(
            *(_process_perspectives(s, cluster_map.get(s.topic_id)) for s in subjects),
            return_exceptions=True,
        )

        perspective_time = time.time() - step_start
        # Axe C — roll-up across all subjects so a single log line is enough
        # to verify that carousel source_count ~ perspective_count on each
        # topic, and to catch regressions on the cluster/GNews merge.
        coherent = sum(
            1
            for s in subjects
            if s.perspective_count >= s.source_count and s.source_count > 0
        )
        logger.info(
            "editorial_pipeline.perspectives_done",
            duration_ms=round(perspective_time * 1000, 2),
            subjects=len(subjects),
            subjects_with_perspectives=sum(1 for s in subjects if s.perspective_count > 0),
            # "coherent" means the header count is at least the cluster count
            # — the invariant we want to hold after this fix.
            subjects_coherent_with_cluster=coherent,
            divergence_analyses=sum(
                1 for s in subjects if s.divergence_analysis
            ),
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
        writer = EditorialWriterService(
            self.session, self.llm, self.config, session_maker=self.session_maker
        )

        selected_topic_ids = {s.topic_id for s in subjects}
        selected_content_ids: set[UUID] = set()
        for s in subjects:
            if s.deep_article:
                selected_content_ids.add(s.deep_article.content_id)

        # Build parallel tasks: writing + pepite + coup de coeur + (actu_decalee if serein)
        parallel_tasks = [
            writer.write_editorial(subjects, mode=mode),
            writer.select_pepite(contents, selected_topic_ids, cluster_data),
            writer.get_coup_de_coeur(selected_content_ids),
        ]
        if mode == "serein":
            parallel_tasks.append(writer.select_actu_decalee(selected_content_ids))

        gather_results = await asyncio.gather(*parallel_tasks, return_exceptions=True)

        writing_raw = gather_results[0]
        pepite_raw = gather_results[1]
        coup_de_coeur_raw = gather_results[2]
        actu_decalee_raw = gather_results[3] if mode == "serein" else None

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

        # Handle actu décalée (serein mode only)
        actu_decalee: ActuDecaleeArticle | None = None
        if isinstance(actu_decalee_raw, ActuDecaleeArticle):
            actu_decalee = actu_decalee_raw
        elif isinstance(actu_decalee_raw, Exception):
            logger.error(
                "editorial_pipeline.actu_decalee_exception",
                error=str(actu_decalee_raw),
            )

        writing_time = time.time() - step_start
        logger.info(
            "editorial_pipeline.writing_done",
            has_writing=writing_result is not None,
            has_pepite=pepite is not None,
            has_coup_de_coeur=coup_de_coeur is not None,
            has_actu_decalee=actu_decalee is not None,
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
            actu_decalee=actu_decalee,
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
            actu_decalee=global_ctx.actu_decalee,
        )

    async def close(self) -> None:
        """Cleanup resources."""
        await self.llm.close()
