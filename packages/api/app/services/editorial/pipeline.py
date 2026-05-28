"""Editorial digest pipeline orchestrator — Stories 10.23 + 10.24.

Orchestrates: clustering → LLM curation → actu matching → perspective analysis.

Global phase (compute_global_context): 1x per batch, shared across users.
Per-user phase (run_for_user): actu matching only, no LLM.

Note: writing/pépite/coup_de_coeur/actu_decalee stages and the "Pas de recul"
deep_matcher integration were removed/disabled during the post-unification
cleanup. Deep matching is preserved in `deep_matcher.py` for the next
"Pas de recul" iteration (see TODO blocks below).
"""

from __future__ import annotations

import asyncio
import os
import time
from contextlib import asynccontextmanager
from datetime import UTC, datetime
from urllib.parse import urlparse
from uuid import UUID

import structlog
from sqlalchemy import case as sa_case
from sqlalchemy import or_, select, update
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.models.content import Content
from app.models.source import Source
from app.services.briefing.importance_detector import ImportanceDetector, TopicCluster
from app.services.editorial.actu_matcher import ActuMatcher
from app.services.editorial.config import load_editorial_config
from app.services.editorial.curation import CurationService, _cluster_to_une_topic
from app.services.editorial.llm_client import EditorialLLMClient
from app.services.editorial.schemas import (
    EditorialGlobalContext,
    EditorialPipelineResult,
    EditorialSubject,
    PerspectiveSourceMini,
    compute_bias_distribution,
    compute_bias_highlights,
    compute_divergence_level,
)
from app.services.llm_bias_annotation_service import LLMBiasAnnotationService
from app.services.perspective_service import Perspective, PerspectiveService
from app.services.title_annotation_service import (
    TitleAnnotationService,
    get_title_annotation_service,
)

logger = structlog.get_logger()

# Curation oversample : on demande +buffer sujets de plus que la cible pour
# absorber les échecs d'actu/deep matching. EDITORIAL_TARGET_SUBJECT_COUNT=5
# permet un rollback safe au comportement pré-passage 5→10.
_DEFAULT_TARGET_SUBJECT_COUNT = 10
_DEFAULT_SUBJECT_BUFFER = 4


def _read_int_env(name: str, default: int, *, floor: int = 0) -> int:
    try:
        return max(floor, int(os.environ.get(name, "")))
    except ValueError:
        return default


def _read_target_subject_count() -> int:
    return _read_int_env(
        "EDITORIAL_TARGET_SUBJECT_COUNT", _DEFAULT_TARGET_SUBJECT_COUNT, floor=1
    )


def _read_subject_buffer() -> int:
    return _read_int_env("EDITORIAL_SUBJECT_BUFFER", _DEFAULT_SUBJECT_BUFFER)


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

        Performs the LLM curation + actu matching + perspective analysis steps.
        Result is reused for all users.

        Args:
            contents: Recent articles for clustering (typically < 48h).
            mode: "pour_vous" or "serein" — affects À la Une selection (bonne
                nouvelle vs trending) and cluster filtering.

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
        # low-priority pool would be too small pour atteindre la cible sujets.
        sorted_by_size = sorted(clusters, key=lambda c: len(c.source_ids), reverse=True)
        capped = cap_low_priority_clusters(sorted_by_size)
        if len(capped) >= _read_target_subject_count():
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

        # ÉTAPE 1B: Pré-sélection "À la Une" — cluster le plus couvert.
        # Cas standard : on prend parmi les clusters "trending" (≥3 sources).
        # Cas creux (week-end / jours fériés) : si aucun cluster ≥3, on
        # rétrograde sur le seuil "multi_source" (≥2) pour ne PAS perdre
        # la promesse revue de presse — un sujet repris par 2 médias reste
        # plus fort qu'un singleton. Cf. bug-digest-pipeline-fallbacks.md.
        step_start = time.time()
        trending_clusters = [c for c in clusters if c.is_trending]
        multi_source_clusters = [c for c in clusters if c.is_multi_source]
        a_la_une_pool = trending_clusters or multi_source_clusters
        a_la_une_fallback = not trending_clusters and bool(multi_source_clusters)
        a_la_une_topic = None

        if mode == "serein":
            if a_la_une_pool:
                top3 = sorted(
                    a_la_une_pool,
                    key=lambda c: len(c.source_ids),
                    reverse=True,
                )[:3]
                a_la_une_topic = await self.curation.select_bonne_nouvelle(top3)
                if not a_la_une_topic:
                    a_la_une_topic = _cluster_to_une_topic(top3[0])
            else:
                logger.info(
                    "editorial_pipeline.bonne_nouvelle_no_multi_source_cluster",
                    trending=len(trending_clusters),
                )
        elif a_la_une_pool:
            top3 = sorted(a_la_une_pool, key=lambda c: len(c.source_ids), reverse=True)[
                :3
            ]

            if len(top3) == 1:
                a_la_une_topic = _cluster_to_une_topic(top3[0])
            else:
                a_la_une_topic = await self.curation.select_a_la_une(top3)
                if not a_la_une_topic:
                    a_la_une_topic = _cluster_to_une_topic(top3[0])

        if a_la_une_topic and a_la_une_fallback:
            logger.info(
                "editorial_pipeline.a_la_une_fallback_multi_source",
                source_count=a_la_une_topic.source_count,
                trending_count=len(trending_clusters),
                multi_source_count=len(multi_source_clusters),
            )

        if a_la_une_topic:
            logger.info(
                "editorial_pipeline.a_la_une_selected",
                topic_id=a_la_une_topic.topic_id,
                source_count=a_la_une_topic.source_count,
                label=a_la_une_topic.label,
            )

        une_time = time.time() - step_start

        # ÉTAPE 2: LLM curation — select remaining topics + buffer.
        # On oversample de `subject_buffer` clusters supplémentaires : si
        # actu/deep matching échoue sur un sujet (cluster sans article éligible
        # < 24h, deep_match LLM négatif), on a une réserve pour garder le
        # digest à target sujets sans replonger en LLM.
        # Cf. bug-digest-pipeline-fallbacks.md.
        step_start = time.time()
        excluded_ids = {a_la_une_topic.topic_id} if a_la_une_topic else set()
        target_subject_count = _read_target_subject_count()
        subject_buffer = _read_subject_buffer()
        remaining_count = (
            (target_subject_count - 1) if a_la_une_topic else target_subject_count
        )
        oversample_count = remaining_count + subject_buffer
        selected_topics = await self.curation.select_topics(
            clusters,
            subjects_count=oversample_count,
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

        cluster_map = {c.cluster_id: c for c in clusters}

        # Persiste `cluster_id` sur les Content sélectionnés — condition sine
        # qua non pour que `_attach_highlight_spans` (router perspectives)
        # retrouve les rows `cluster_title_annotations` écrites par l'étape
        # 3B-bis. `cluster_signature` filtre les annotations obsolètes côté
        # lecture si la composition change à un run ultérieur.
        selected_content_cluster_pairs: list[tuple[UUID, UUID]] = []
        selected_cluster_ids: set[UUID] = set()
        for topic in selected_topics:
            cluster = cluster_map.get(topic.topic_id)
            if not cluster or len(cluster.contents) < 2:
                continue
            cluster_uuid = UUID(cluster.cluster_id)
            selected_cluster_ids.add(cluster_uuid)
            for c in cluster.contents:
                selected_content_cluster_pairs.append((c.id, cluster_uuid))

        if selected_content_cluster_pairs:
            async with self._short_session() as session:
                await _persist_content_cluster_ids(
                    session, selected_content_cluster_pairs
                )
            logger.info(
                "editorial_pipeline.content_cluster_ids_persisted",
                content_count=len(selected_content_cluster_pairs),
                cluster_count=len(selected_cluster_ids),
            )

        # ÉTAPE 3B-bis: LLM bias annotation pour les clusters sélectionnés.
        # Skip silencieux si MISTRAL_API_KEY absente (fallback spaCy hors-ligne
        # géré ailleurs). Référence = cluster.label (best title du TopicSelector).
        llm_bias_step_start = time.time()
        llm_bias_service = LLMBiasAnnotationService()
        title_service = get_title_annotation_service()
        llm_bias_stats = {
            "cluster_count": 0,
            "variants_annotated": 0,
            "variants_skipped": 0,
            "cache_hits": 0,
        }
        if llm_bias_service.is_ready:
            for topic in selected_topics:
                cluster = cluster_map.get(topic.topic_id)
                if not cluster or len(cluster.contents) < 2:
                    continue
                llm_bias_stats["cluster_count"] += 1
                try:
                    await _annotate_cluster_llm_bias(
                        cluster=cluster,
                        llm_service=llm_bias_service,
                        title_service=title_service,
                        short_session=self._short_session,
                        stats=llm_bias_stats,
                    )
                except Exception:
                    logger.exception(
                        "editorial_pipeline.llm_bias_failed",
                        cluster_id=str(cluster.cluster_id),
                    )
        logger.info(
            "editorial_pipeline.llm_bias_done",
            duration_ms=round((time.time() - llm_bias_step_start) * 1000, 2),
            llm_version=LLMBiasAnnotationService.LLM_VERSION,
            **llm_bias_stats,
        )

        cluster_map_counts = {c.cluster_id: len(c.source_ids) for c in clusters}
        subjects = [
            EditorialSubject(
                rank=i + 1,
                topic_id=topic.topic_id,
                label=topic.label,
                selection_reason=topic.selection_reason,
                deep_angle=topic.deep_angle,
                deep_article=None,
                source_count=topic.source_count
                or cluster_map_counts.get(topic.topic_id, 0),
                theme=topic.theme,
                is_a_la_une=(i == 0 and a_la_une_topic is not None),
            )
            for i, topic in enumerate(selected_topics)
        ]

        # ÉTAPE 3A: Actu matching GLOBAL (not per-user — MVP V2)
        step_start = time.time()
        subjects = self.actu_matcher.match_global(
            subjects=subjects,
            clusters=clusters,
            excluded_source_ids=set(),
            excluded_content_ids=set(),
        )
        actu_time = time.time() - step_start
        actu_hit_count = sum(1 for s in subjects if s.actu_article is not None)
        logger.info(
            "editorial_pipeline.actu_matching_done",
            hits=actu_hit_count,
            total=len(subjects),
            duration_ms=round(actu_time * 1000, 2),
        )

        # ÉTAPE 3A-bis: trim au target_subject_count.
        # On a oversamplé de subject_buffer ; on exige qu'un sujet ait un
        # `actu_article` (parution récente). Un sujet avec seulement un
        # `deep_article` (parfois plusieurs jours) ne mérite pas d'être
        # promu en article principal — sa place est sur le rail "Prendre
        # du recul", pas dans les sujets du jour. Cf. bug-essentiel-pipeline.md.
        # Le buffer permet généralement de combler les drops ; si on retombe
        # quand même < target, on logge en error pour visibilité.
        empty_dropped: list[str] = []
        kept: list[EditorialSubject] = []
        for s in subjects:
            if s.actu_article is None:
                empty_dropped.append(s.label or s.topic_id)
                logger.warning(
                    "editorial_pipeline.subject_no_actu",
                    topic_id=s.topic_id,
                    label=s.label,
                    had_deep=s.deep_article is not None,
                )
                continue
            kept.append(s)
            if len(kept) >= target_subject_count:
                break

        # Renumérotation : les rangs doivent être 1..len(kept) après le trim,
        # sinon le mobile affiche "Sujet 1, 3, 4" si rang 2 a été droppé.
        renumbered: list[EditorialSubject] = []
        for new_rank, s in enumerate(kept, start=1):
            renumbered.append(
                s.model_copy(
                    update={
                        "rank": new_rank,
                        # is_a_la_une reste vrai uniquement si on est rang 1
                        # ET que c'était bien le sujet À la Une initial.
                        "is_a_la_une": s.is_a_la_une and new_rank == 1,
                    }
                )
            )
        subjects = renumbered

        if len(subjects) < target_subject_count:
            logger.error(
                "editorial_pipeline.subjects_under_target",
                kept=len(subjects),
                target=target_subject_count,
                dropped=empty_dropped,
            )
        elif empty_dropped:
            logger.info(
                "editorial_pipeline.subjects_buffer_used",
                kept=len(subjects),
                dropped_count=len(empty_dropped),
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
                (
                    gnews_perspectives,
                    _,
                ) = await perspective_service.get_perspectives_hybrid(
                    content=representative,
                    exclude_domain=exclude_domain,
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

            # Safety net: if every merged perspective has an unknown bias
            # (source not in DOMAIN_BIAS_MAP nor resolvable via DB), fall
            # back to counting the cluster sources themselves. Otherwise
            # the card footer would show a single logo even when the digest
            # actually grouped several outlets together. The bias
            # distribution stays all-zero so the spectrum bar and divergence
            # analysis remain hidden — we only lift the raw source counter.
            # Cf. docs/bugs/bug-digest-perspective-undercount.md (Axe 2).
            if not known_perspectives and cluster_perspectives:
                subject.perspective_count = len(cluster_perspectives)
                subject.bias_distribution = compute_bias_distribution([])
                subject.bias_highlights = None
                logger.info(
                    "editorial_pipeline.perspective_count_safety_net",
                    topic_id=subject.topic_id,
                    cluster_sources=len(cluster_perspectives),
                )
            else:
                subject.perspective_count = len(known_perspectives)
                subject.bias_distribution = compute_bias_distribution(
                    known_perspectives
                )
                subject.bias_highlights = compute_bias_highlights(
                    subject.bias_distribution
                )

            # Persist the full known-bias merged list so the
            # /contents/{id}/perspectives endpoint can return the exact same
            # snapshot — otherwise the bottom sheet re-runs Google News at
            # call time and shows different media than the CTA logos that
            # come from this pipeline run.
            # When the safety net above kicked in (no known bias), persist
            # the cluster perspectives as-is (bias_stance=unknown) so the
            # endpoint doesn't bail out to the live path — it already has
            # the full cluster list to return, and the mobile footer logos
            # stay coherent with the digest-time cluster.
            snapshot_perspectives = (
                known_perspectives if known_perspectives else cluster_perspectives
            )
            subject.perspective_articles = [
                {
                    "title": p.title,
                    "url": p.url,
                    "source_name": p.source_name,
                    "source_domain": p.source_domain,
                    "bias_stance": p.bias_stance,
                    "published_at": p.published_at,
                    "description": p.description,
                }
                for p in snapshot_perspectives
            ]

            # Axe C — observability: log the composition so we can verify in
            # prod que cluster count, perspective count et LLM analysis
            # décrivent le même media set. final_persisted_count = ce que
            # le fast path retournera (doit toujours == perspective_count).
            logger.info(
                "editorial_pipeline.perspectives_composition",
                topic_id=subject.topic_id,
                cluster_sources=len(cluster_perspectives),
                gnews_added=len(new_gnews),
                total_merged=len(merged_perspectives),
                known_bias=len(known_perspectives),
                unknown_bias=len(merged_perspectives) - len(known_perspectives),
                final_persisted_count=len(subject.perspective_articles or []),
                perspective_count=subject.perspective_count,
            )

            # Build perspective_sources — max 6, deduplicated by domain.
            # Use known_perspectives so the CTA logos match the bottom sheet
            # (which also filters out unknown bias). When the safety net
            # above fell back to cluster sources (no known bias), feed the
            # same list here so the footer renders logos for each outlet
            # in the cluster, consistent with perspective_count.
            sources_pool = known_perspectives or cluster_perspectives
            seen_domains: set[str] = set()
            unique_perspectives = []
            for p in sources_pool:
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
            subjects_with_perspectives=sum(
                1 for s in subjects if s.perspective_count > 0
            ),
            # "coherent" means the header count is at least the cluster count
            # — the invariant we want to hold after this fix.
            subjects_coherent_with_cluster=coherent,
            divergence_analyses=sum(1 for s in subjects if s.divergence_analysis),
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

        total_time = time.time() - start
        logger.info(
            "editorial_pipeline.global_context_ready",
            subjects=len(subjects),
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


async def _persist_content_cluster_ids(
    session: AsyncSession,
    pairs: list[tuple[UUID, UUID]],
) -> None:
    """UPDATE bulk `contents.cluster_id` pour les articles d'un run.

    Idempotent : ré-applique le même `cluster_id` si déjà set. Les anciennes
    valeurs sont écrasées — au prochain run, `cluster_signature` côté CTA
    invalide les annotations dont la composition a changé.
    """
    if not pairs:
        return
    when_clauses = dict(pairs)
    stmt = (
        update(Content)
        .where(Content.id.in_(when_clauses.keys()))
        .values(cluster_id=sa_case(when_clauses, value=Content.id))
    )
    await session.execute(stmt)
    await session.commit()


async def _annotate_cluster_llm_bias(
    *,
    cluster: TopicCluster,
    llm_service: LLMBiasAnnotationService,
    title_service: TitleAnnotationService,
    short_session,
    stats: dict[str, int],
) -> None:
    """Annote tous les variants d'un cluster avec le LLM bias service.

    Pré-condition assurée ici : `get_or_compute_cluster_annotations` crée
    les rows spaCy (UPDATE-only de `write_llm_annotations` exige des rows
    existantes). Skip variant self-référent (`title == cluster.label`)
    et utilise le cache si la signature est stable.
    """
    ref_title = cluster.label or ""
    if not ref_title:
        return

    cluster_id_uuid = UUID(cluster.cluster_id)
    signature = title_service.compute_cluster_signature(
        [c.id for c in cluster.contents]
    )
    # Garde nécessaire : si tous les variants partagent le titre du best
    # title (cluster artificiel à doublons), `expected == 0` et len(cached)
    # est trivialement ≥ 0 — sans la garde on incrémenterait à tort.
    expected = sum(1 for c in cluster.contents if c.title and c.title != ref_title)
    if expected == 0:
        return

    async with short_session() as session:
        cached = await title_service.get_llm_annotations(
            session, cluster_id_uuid, LLMBiasAnnotationService.LLM_VERSION, signature
        )
        if len(cached) >= expected:
            stats["cache_hits"] += 1
            return

        # `write_llm_annotations` est UPDATE-only — pré-condition PR 3 :
        # les rows `cluster_title_annotations` doivent exister avec
        # `strong_tokens` (spaCy). On les garantit ici juste avant l'écriture.
        await title_service.get_or_compute_cluster_annotations(session, cluster_id_uuid)

        annotations: dict[UUID, dict] = {}
        for variant in cluster.contents:
            if not variant.title or variant.title == ref_title:
                continue
            if variant.id in cached:
                continue
            peers = [
                c.title for c in cluster.contents if c.id != variant.id and c.title
            ][:3]
            stance = getattr(variant.source, "bias_stance", None)
            bias_stance = getattr(stance, "value", stance) or "unknown"
            result = await llm_service.annotate_variant(
                ref_title=ref_title,
                variant_title=variant.title,
                bias_stance=bias_stance,
                peers=peers,
            )
            if result is None:
                stats["variants_skipped"] += 1
                logger.warning(
                    "editorial_pipeline.llm_bias_variant_skipped",
                    cluster_id=str(cluster.cluster_id),
                    content_id=str(variant.id),
                )
                continue
            annotations[variant.id] = result
            stats["variants_annotated"] += 1

        if annotations:
            await title_service.write_llm_annotations(
                session,
                cluster_id_uuid,
                LLMBiasAnnotationService.LLM_VERSION,
                signature,
                annotations,
            )
