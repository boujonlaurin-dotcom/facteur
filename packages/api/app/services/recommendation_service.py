import asyncio
import datetime
import re
import time
import unicodedata
from uuid import UUID

import structlog
from sqlalchemy import desc, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.content import Content, UserContentStatus
from app.models.enums import ContentStatus, ContentType, FeedFilterMode
from app.models.source import Source, UserSource
from app.models.user import UserProfile, UserSubtopic

logger = structlog.get_logger()

from app.schemas.content import RecommendationReason, ScoreContribution
from app.services.recommendation.filter_presets import (
    apply_entity_filter,
    apply_keyword_filter,
    apply_serein_filter,
    apply_theme_focus_filter,
    apply_topic_filter,
    calculate_user_bias,
    get_opposing_biases,
)
from app.services.recommendation.layers import (
    ArticleTopicLayer,
    BehavioralLayer,
    ContentQualityLayer,
    CoreLayer,
    ImpressionLayer,
    PersonalizationLayer,
    QualityLayer,
    StaticPreferenceLayer,
    UserCustomTopicLayer,
    VisualLayer,
)
from app.services.recommendation.scoring_config import ScoringWeights
from app.services.recommendation.scoring_engine import (
    PillarScoringEngine,
    ScoringContext,
    ScoringEngine,
)


class RecommendationService:
    def __init__(self, session: AsyncSession):
        self.session = session
        self.user_custom_topics: list = []  # Populated by get_feed() for reuse by caller
        self.source_overflow: dict[
            UUID, int
        ] = {}  # Populated by chronological diversification
        self.topic_overflow: list[
            dict
        ] = []  # Populated by topic regroupement (Phase 2)
        self.total_candidates: int = 0  # Total candidate pool size (pre-filtering)
        self.keyword_overflow: list[dict] = []  # Populated by keyword regroupement
        self.entity_overflow: list[dict] = []  # Populated by entity regroupement
        self.carousels: list[dict] = []  # Populated by _build_carousels()
        # Initialisation du moteur avec les couches configurées
        # L'ordre n'affecte pas le score (somme), mais affecte les logs/debugging
        self.scoring_engine = ScoringEngine(
            [
                CoreLayer(),
                StaticPreferenceLayer(),
                BehavioralLayer(),
                QualityLayer(),
                VisualLayer(),
                ContentQualityLayer(),
                ArticleTopicLayer(),
                PersonalizationLayer(),  # Story 4.7
                ImpressionLayer(),  # Feed Refresh
                UserCustomTopicLayer(),  # Epic 11
            ]
        )
        # Pillar-based scoring engine (v2)
        self.pillar_engine = PillarScoringEngine()

    async def get_feed(
        self,
        user_id: UUID,
        limit: int = 20,
        offset: int = 0,
        content_type: str | None = None,
        mode: FeedFilterMode | None = None,
        saved_only: bool = False,
        theme: str | None = None,
        topic: str | None = None,
        has_note: bool = False,
        source_id: str | None = None,
        entity: str | None = None,
        keyword: str | None = None,
        serein: bool = False,
    ) -> list[Content]:
        """
        Génère un feed personnalisé pour l'utilisateur.

        Algorithme V2 (Modular Scoring):
        1. Récupérer les candidats.
        2. Scorer via ScoringEngine (Core + Prefs + Behavioral).
        3. Appliquer la pénalité de fatigue de source (Diversité).
        4. Trier et paginer.
        """
        # 1. Fetch user context in parallel using separate sessions
        # Each query gets its own session from the pool to avoid AsyncSession
        # concurrency issues while cutting ~800ms of sequential round-trips.
        from datetime import date as date_module

        from sqlalchemy.orm import joinedload

        from app.database import async_session_maker
        from app.models.daily_digest import DailyDigest
        from app.models.user_personalization import UserPersonalization

        t0 = time.monotonic()

        profile_stmt = (
            select(UserProfile)
            .options(
                joinedload(UserProfile.interests), joinedload(UserProfile.preferences)
            )
            .where(UserProfile.user_id == user_id)
        )
        sources_stmt = select(
            UserSource.source_id, UserSource.is_custom, UserSource.has_subscription
        ).where(UserSource.user_id == user_id)
        subtopics_stmt = select(UserSubtopic).where(UserSubtopic.user_id == user_id)
        personalization_stmt = select(UserPersonalization).where(
            UserPersonalization.user_id == user_id
        )
        digest_stmt = select(DailyDigest).where(
            DailyDigest.user_id == user_id,
            DailyDigest.target_date == date_module.today(),
        )

        async def _pread_scalar(stmt):
            async with async_session_maker() as s:
                return await s.scalar(stmt)

        async def _pread_rows(stmt):
            async with async_session_maker() as s:
                return (await s.execute(stmt)).all()

        async def _pread_scalars_all(stmt):
            async with async_session_maker() as s:
                return (await s.scalars(stmt)).all()

        (
            user_profile,
            followed_sources_rows,
            subtopics_rows,
            personalization,
            digest_row,
        ) = await asyncio.gather(
            _pread_scalar(profile_stmt),
            _pread_rows(sources_stmt),
            _pread_scalars_all(subtopics_stmt),
            _pread_scalar(personalization_stmt),
            _pread_scalar(digest_stmt),
        )

        t1 = time.monotonic()
        logger.info("feed_phase1_context", duration_ms=round((t1 - t0) * 1000))

        # Process results
        followed_source_ids = set()
        custom_source_ids = set()
        subscribed_source_ids = set()
        for row in followed_sources_rows:
            followed_source_ids.add(row.source_id)
            if row.is_custom:
                custom_source_ids.add(row.source_id)
            if row.has_subscription:
                subscribed_source_ids.add(row.source_id)

        user_subtopics = set()
        user_subtopic_weights: dict[str, float] = {}
        for row in subtopics_rows:
            user_subtopics.add(row.topic_slug)
            user_subtopic_weights[row.topic_slug] = row.weight

        user_interests = set()
        user_interest_weights = {}
        user_prefs = {}

        if user_profile:
            for i in user_profile.interests:
                user_interests.add(i.interest_slug)
                user_interest_weights[i.interest_slug] = i.weight

            for p in user_profile.preferences:
                user_prefs[p.preference_key] = p.preference_value

        if saved_only:
            # Fetch saved items directly
            stmt = (
                select(UserContentStatus)
                .options(
                    selectinload(UserContentStatus.content).options(
                        selectinload(Content.source)
                    )
                )
                .where(UserContentStatus.user_id == user_id, UserContentStatus.is_saved)
            )
            if has_note:
                stmt = stmt.where(
                    UserContentStatus.note_text.isnot(None),
                    UserContentStatus.note_text != "",
                )
            stmt = (
                stmt.order_by(
                    desc(
                        func.coalesce(
                            UserContentStatus.saved_at, UserContentStatus.updated_at
                        )
                    )
                )
                .offset(offset)
                .limit(limit)
            )

            statuses = await self.session.scalars(stmt)
            results = []
            for st in statuses:
                content = st.content
                # Populate transient fields
                content.is_saved = True
                content.is_hidden = st.is_hidden
                content.hidden_reason = st.hidden_reason
                content.status = st.status
                content.reading_progress = st.reading_progress
                content.note_text = st.note_text
                content.note_updated_at = st.note_updated_at
                results.append(content)

            return results

        # 2. Process digest exclusion (already fetched in Phase 1)
        digest_content_ids: list[UUID] = []
        try:
            if digest_row and digest_row.items:
                digest_content_ids = [
                    UUID(item["content_id"]) for item in digest_row.items
                ]
        except Exception as e:
            logger.warning("feed_digest_exclusion_failed", error=str(e))

        # Story 4.7: Personalization filters
        muted_sources = (
            set(personalization.muted_sources)
            if personalization and personalization.muted_sources
            else set()
        )
        muted_themes = (
            {t.lower() for t in personalization.muted_themes}
            if personalization and personalization.muted_themes
            else set()
        )
        muted_topics = (
            {t.lower() for t in personalization.muted_topics}
            if personalization and personalization.muted_topics
            else set()
        )
        muted_content_types = (
            {t.lower() for t in personalization.muted_content_types}
            if personalization and personalization.muted_content_types
            else set()
        )

        # Paywall filter preference
        # Disable paywall filter when browsing a specific source (exploration mode)
        hide_paid_content = True  # Default: hide paid articles
        if source_id:
            hide_paid_content = False
        elif personalization and personalization.hide_paid_content is not None:
            hide_paid_content = personalization.hide_paid_content

        # Convert source_id string to UUID if provided
        source_uuid = UUID(source_id) if source_id else None

        t2 = time.monotonic()
        candidates = await self._get_candidates(
            user_id,
            limit_candidates=500,
            content_type=content_type,
            mode=mode,
            followed_source_ids=followed_source_ids,
            # Story 4.7 : Filter out muted items at DB level
            muted_sources=muted_sources,
            muted_themes=muted_themes,
            muted_topics=muted_topics,
            muted_content_types=muted_content_types,
            # Story 10.20 : Exclude today's digest articles from feed
            digest_content_ids=digest_content_ids,
            # Story 11 : Feed par thème
            theme=theme,
            # Topic filter (granular, e.g. 'startups', 'entrepreneurship')
            topic=topic,
            # Entity filter: signal explicit_filter mode
            entity=entity,
            # Keyword filter (title ILIKE match for keyword overflow chip taps)
            keyword=keyword,
            # Paywall filter
            hide_paid_content=hide_paid_content,
            # Premium sources: allow paid content from subscribed sources
            subscribed_source_ids=subscribed_source_ids,
            # Source filter
            source_id=source_uuid,
            # Serein content filter (orthogonal to mode)
            serein=serein,
        )
        self.total_candidates = len(candidates)

        # Entity filter: post-filter candidates by entity name in content.entities[]
        if entity:
            import json as _json

            entity_lower = entity.lower()

            def _matches_entity(c: Content) -> bool:
                if not c.entities:
                    return False
                for raw in c.entities:
                    try:
                        e = _json.loads(raw)
                        if (
                            isinstance(e, dict)
                            and e.get("name", "").lower() == entity_lower
                        ):
                            return True
                    except (ValueError, TypeError):
                        continue
                return False

            candidates = [c for c in candidates if _matches_entity(c)]

        # Explicit filter OR RECENT mode: skip scoring, return pure chronological order
        # Candidates are already sorted by published_at DESC from _get_candidates
        if source_uuid or theme or topic or entity or mode == FeedFilterMode.RECENT:
            paginated = candidates[offset : offset + limit]
            await self._hydrate_user_status(paginated, user_id, followed_source_ids)
            return paginated

        # Load source priority multipliers (needed for both chrono and scoring paths)
        source_weight_rows = (
            await self.session.execute(
                select(UserSource.source_id, UserSource.priority_multiplier).where(
                    UserSource.user_id == user_id
                )
            )
        ).all()
        source_priority_multipliers = {
            row.source_id: row.priority_multiplier for row in source_weight_rows
        }

        # Epic 12: Chronological diversified mode (new default)
        # mode=None means no chip selected → chronological diversified
        if mode is None or mode == FeedFilterMode.CHRONOLOGICAL:
            t3 = time.monotonic()
            logger.info(
                "feed_phase2_candidates",
                duration_ms=round((t3 - t2) * 1000),
                count=len(candidates),
                mode="chronological",
            )

            # Phase 1: Chronological diversification with expanded pool for Phase 2
            # Request more articles than limit so Phase 2 has room to compress neutrals
            phase1_limit = limit * 3
            result, source_overflow = self._apply_chronological_diversification(
                candidates, source_priority_multipliers, phase1_limit, offset
            )
            self.source_overflow = source_overflow
            await self._hydrate_user_status(result, user_id, followed_source_ids)

            # Source interleaving: avoid consecutive articles from same source
            result = self._apply_source_interleaving(result)

            # Load custom topics for cluster building (reuse by caller)
            from app.models.user_topic_profile import UserTopicProfile

            custom_topics_stmt = select(UserTopicProfile).where(
                UserTopicProfile.user_id == user_id
            )
            user_custom_topics = list(await _pread_scalars_all(custom_topics_stmt))
            self.user_custom_topics = user_custom_topics

            # Snapshot all articles before regroupement removes hidden ones
            pre_regroup_map = {a.id: a for a in result}

            # Phase 1.5: Entity regroupement (highest thematic priority)
            result, entity_overflow, assigned_ids, entity_ctas = (
                self._apply_entity_regroupement(result, ScoringWeights.MAX_TOTAL_CTAS)
            )
            self.entity_overflow = entity_overflow

            # Phase 2: Keyword regroupement (remaining CTA budget)
            remaining_budget = ScoringWeights.MAX_TOTAL_CTAS - entity_ctas
            result, keyword_overflow, topic_overflow = self._apply_keyword_regroupement(
                result,
                user_custom_topics,
                user_subtopic_weights,
                limit,
                pre_assigned_ids=assigned_ids,
                max_ctas=remaining_budget,
            )
            self.keyword_overflow = keyword_overflow
            self.topic_overflow = topic_overflow

            # Phase 2.5: Promote overflow groups to carousels
            has_filter = any([theme, topic, source_id, entity, keyword, saved_only])
            if not has_filter:
                result, carousel_data = await self._build_carousels(
                    result, pre_regroup_map, user_id=user_id
                )
                self.carousels = carousel_data

            # Phase 3: Suppress redundant source CTAs
            self._suppress_redundant_source_overflow()

            # Phase 3b: Safety net — force-group 3+ consecutive same-source
            result, extra_source_overflow = self._apply_source_safety_net(result)
            for sid, count in extra_source_overflow.items():
                self.source_overflow[sid] = self.source_overflow.get(sid, 0) + count

            t_end = time.monotonic()
            logger.info(
                "feed_total",
                duration_ms=round((t_end - t0) * 1000),
                items=len(result),
                mode="chronological",
                keyword_overflow_count=len(keyword_overflow),
                topic_overflow_count=len(topic_overflow),
                entity_overflow_count=len(entity_overflow),
                entity_overflow_details=[
                    {"name": g["entity_name"], "hidden": g["hidden_count"], "sources": len(g.get("sources", []))}
                    for g in entity_overflow[:5]
                ],
                carousel_count=len(self.carousels),
                carousel_types=[c["carousel_type"] for c in self.carousels],
            )
            return result

        # 3. Score Candidates using ScoringEngine (POUR_VOUS + other modes)
        t3 = time.monotonic()
        logger.info(
            "feed_phase2_candidates",
            duration_ms=round((t3 - t2) * 1000),
            count=len(candidates),
        )

        scored_candidates = []
        now = datetime.datetime.now(datetime.UTC)

        # Phase 3: Parallel scoring context queries (separate sessions)
        from app.models.user_topic_profile import UserTopicProfile

        source_affinity_stmt = self._source_affinity_stmt(user_id)
        impression_ids = [c.id for c in candidates]
        custom_topics_stmt = select(UserTopicProfile).where(
            UserTopicProfile.user_id == user_id
        )

        async def _pread_source_affinity():
            async with async_session_maker() as s:
                rows = (await s.execute(source_affinity_stmt)).all()
                return self._normalize_affinity(rows)

        async def _pread_impressions():
            if not impression_ids:
                return {}
            async with async_session_maker() as s:
                stmt = select(
                    UserContentStatus.content_id,
                    UserContentStatus.last_impressed_at,
                    UserContentStatus.manually_impressed,
                ).where(
                    UserContentStatus.user_id == user_id,
                    UserContentStatus.content_id.in_(impression_ids),
                    UserContentStatus.last_impressed_at.isnot(None),
                )
                rows = (await s.execute(stmt)).all()
                return {
                    row.content_id: (row.last_impressed_at, row.manually_impressed)
                    for row in rows
                }

        (
            source_affinity_scores,
            impression_data,
            user_custom_topics_rows,
        ) = await asyncio.gather(
            _pread_source_affinity(),
            _pread_impressions(),
            _pread_scalars_all(custom_topics_stmt),
        )
        user_custom_topics = list(user_custom_topics_rows)
        self.user_custom_topics = user_custom_topics  # Expose for caller reuse

        t4 = time.monotonic()
        logger.info("feed_phase3_scoring_context", duration_ms=round((t4 - t3) * 1000))

        # Context creation
        context = ScoringContext(
            user_profile=user_profile,
            user_interests=user_interests,
            user_interest_weights=user_interest_weights,
            followed_source_ids=followed_source_ids,
            user_prefs=user_prefs,
            now=now,
            user_subtopics=user_subtopics,
            user_subtopic_weights=user_subtopic_weights,
            # Story 4.7
            muted_sources=muted_sources,
            muted_themes=muted_themes,
            muted_topics=muted_topics,
            muted_content_types=muted_content_types,
            custom_source_ids=custom_source_ids,
            source_affinity_scores=source_affinity_scores,
            impression_data=impression_data,
            user_custom_topics=user_custom_topics,
            source_priority_multipliers=source_priority_multipliers,
            subscribed_source_ids=subscribed_source_ids,
        )

        use_pillars = ScoringWeights.SCORING_VERSION == "pillars_v1"

        # Store pillar results for reason hydration (v2 only)
        pillar_results: dict = {}  # {content_id: PillarScoreResult}

        for content in candidates:
            if use_pillars:
                pillar_result = self.pillar_engine.compute_score(content, context)
                score = pillar_result.final_score
                pillar_results[content.id] = pillar_result
            else:
                score = self.scoring_engine.compute_score(content, context)
            scored_candidates.append((content, score))

        t5 = time.monotonic()
        logger.info(
            "feed_phase4_scoring",
            duration_ms=round((t5 - t4) * 1000),
            candidates=len(candidates),
            engine="pillars_v1" if use_pillars else "layers_v1",
        )

        # 4. Sort by score DESC
        scored_candidates.sort(key=lambda x: x[1], reverse=True)

        # 4b. Diversity Re-ranking (Source Fatigue)
        # Apply a cumulative penalty for multiple items from the same source
        # to ensure a diverse top-of-feed.
        final_list = []
        source_counts = {}
        decay_factor = 0.70  # Each subsequent item from same source loses 30% score (Story diversity fix)

        for content, base_score in scored_candidates:
            source_id = content.source_id
            count = source_counts.get(source_id, 0)

            # FinalScore = BaseScore * (decay_factor ^ count)
            final_score = base_score * (decay_factor**count)

            final_list.append((content, final_score))
            source_counts[source_id] = count + 1

        # Sort again with diversity penalties applied to find the new Top-N
        final_list.sort(key=lambda x: x[1], reverse=True)

        # 4c. Randomization (v2 only — Gumbel noise for discovery)
        if use_pillars and ScoringWeights.FEED_RANDOMIZATION_TEMPERATURE > 0:
            from app.services.recommendation.randomization import randomized_sort

            final_list = randomized_sort(
                final_list,
                temperature=ScoringWeights.FEED_RANDOMIZATION_TEMPERATURE,
                seed=None,  # Random per request for feed discovery
            )

        # 5. Paginate
        scored_candidates = final_list
        start = offset
        end = offset + limit
        # Check bounds
        if start >= len(scored_candidates):
            return []

        result = [item[0] for item in scored_candidates[start:end]]

        # 5.5 Hydrate Recommendation Reason (Transparency)
        if use_pillars:
            # v2: Use reason_builder with pillar results
            from app.services.recommendation.reason_builder import (
                build_recommendation_reason,
            )

            for content in result:
                pr = pillar_results.get(content.id)
                if pr:
                    content.recommendation_reason = build_recommendation_reason(pr)
                    if ScoringWeights.FEED_RANDOMIZATION_TEMPERATURE > 0:
                        content.recommendation_reason.breakdown.append(
                            ScoreContribution(
                                label="Hasard pour diversifier",
                                points=0,
                                is_positive=True,
                                pillar="diversite",
                            )
                        )
        else:
            # v1: Legacy reason hydration from context.reasons
            self._hydrate_legacy_reasons(result, context)

        # 6. Hydrate with User Status (is_saved, etc)
        await self._hydrate_user_status(result, user_id, followed_source_ids)

        t_end = time.monotonic()
        logger.info(
            "feed_total", duration_ms=round((t_end - t0) * 1000), items=len(result)
        )
        return result

    async def _hydrate_user_status(
        self,
        items: list[Content],
        user_id: UUID,
        followed_source_ids: set[UUID] | None = None,
    ) -> None:
        """Hydrate content items with user-specific status (is_saved, is_liked, etc.)."""
        content_ids = [c.id for c in items]
        if not content_ids:
            return
        stmt = select(UserContentStatus).where(
            UserContentStatus.user_id == user_id,
            UserContentStatus.content_id.in_(content_ids),
        )
        statuses = await self.session.scalars(stmt)
        status_map = {s.content_id: s for s in statuses}
        for content in items:
            st = status_map.get(content.id)
            content.is_saved = st.is_saved if st else False
            content.is_liked = st.is_liked if st else False
            content.is_hidden = st.is_hidden if st else False
            content.hidden_reason = st.hidden_reason if st else None
            content.status = st.status if st else ContentStatus.UNSEEN
            if followed_source_ids is not None:
                content.is_followed_source = content.source_id in followed_source_ids

    @staticmethod
    def _apply_chronological_diversification(
        candidates: list[Content],
        source_priority_multipliers: dict[UUID, float],
        limit: int,
        offset: int,
    ) -> tuple[list[Content], dict[UUID, int]]:
        """
        Epic 12: Algorithme "Ratio Normalisé" — chronological feed with source diversification.

        Pipeline:
        1. Group by source, compute relative frequency
        2. Compute quota per source: ceil(frequency × (offset+limit) × priority_multiplier), min 1
        3. Keep the N most recent articles per source (up to quota)
        4. Sort all retained articles by published_at DESC
        5. Paginate with offset (quotas cover offset+limit so slice is never empty)
        """
        from math import ceil

        if not candidates:
            return [], {}

        # PASS 1: Group by source and compute frequencies
        by_source: dict[UUID, list[Content]] = {}
        for article in candidates:
            by_source.setdefault(article.source_id, []).append(article)

        total = len(candidates)
        effective_limit = offset + limit  # Cover all pages up to current request

        # PASS 2: Compute quotas with user multipliers
        quotas: dict[UUID, int] = {}
        for source_id, articles_src in by_source.items():
            ratio = len(articles_src) / total
            multiplier = max(0.1, source_priority_multipliers.get(source_id, 1.0))
            quota = max(1, ceil(ratio * effective_limit * multiplier))
            quotas[source_id] = quota

        logger.debug(
            "diversification_quotas_raw",
            quotas={str(sid): q for sid, q in quotas.items()},
            multipliers={
                str(sid): source_priority_multipliers.get(sid, 1.0) for sid in by_source
            },
        )

        # PASS 2b: Diversity cap — no source gets more than 4× min_quota (× its multiplier)
        MAX_SOURCE_RATIO = 8
        min_quota = min(quotas.values())
        for source_id in quotas:
            multiplier = max(0.1, source_priority_multipliers.get(source_id, 1.0))
            cap = max(1, ceil(MAX_SOURCE_RATIO * min_quota * multiplier))
            quotas[source_id] = min(quotas[source_id], cap)

        # PASS 2c: Normalize quotas so total ≈ limit (prevent overflow
        # when multipliers push sum(quotas) well beyond requested limit)
        total_quota = sum(quotas.values())
        if total_quota > effective_limit:
            scale = effective_limit / total_quota
            quotas = {sid: max(1, ceil(q * scale)) for sid, q in quotas.items()}

        logger.debug(
            "diversification_quotas_normalized",
            quotas={str(sid): q for sid, q in quotas.items()},
            total_quota=sum(quotas.values()),
            effective_limit=effective_limit,
        )

        # PASS 3: Select articles to retain (most recent per source, up to quota)
        # Candidates from _get_candidates are already sorted by published_at DESC,
        # so each source's list preserves that order.
        MIN_OVERFLOW_FOR_CTA = 7
        retained: list[Content] = []
        source_overflow: dict[UUID, int] = {}
        for source_id, articles_src in by_source.items():
            quota = quotas[source_id]
            retained.extend(articles_src[:quota])
            overflow_count = len(articles_src) - quota
            if overflow_count >= MIN_OVERFLOW_FOR_CTA:
                source_overflow[source_id] = overflow_count

        # PASS 4: Final chronological sort
        retained.sort(key=lambda a: a.published_at, reverse=True)

        # PASS 5: Paginate
        return retained[offset : offset + limit], source_overflow

    @staticmethod
    def _apply_source_interleaving(articles: list[Content]) -> list[Content]:
        """
        Prevent more than 2 consecutive articles from the same source.

        For each position i (starting at 2), if article[i] shares the same
        source as article[i-1] and article[i-2], swap with the nearest
        following article from a different source.
        """
        result = list(articles)
        n = len(result)
        for i in range(2, n):
            if (
                result[i].source_id == result[i - 1].source_id
                and result[i].source_id == result[i - 2].source_id
            ):
                # Find the nearest different source to swap with
                for j in range(i + 1, n):
                    if result[j].source_id != result[i].source_id:
                        result[i], result[j] = result[j], result[i]
                        break
        return result

    @staticmethod
    def _apply_entity_regroupement(
        retained: list[Content],
        max_ctas: int,
    ) -> tuple[list[Content], list[dict], set[UUID], int]:
        """
        Entity-based feed regroupement (highest thematic priority).

        Groups articles sharing the same named entity (from content.entities JSON).
        Returns: (filtered_articles, entity_overflow_info, assigned_ids, ctas_used)
        """
        import json as _json

        min_group = ScoringWeights.MIN_FOR_ENTITY_GROUPING

        # Step 1: Build entity → articles index
        entity_to_articles: dict[str, list[Content]] = {}
        for article in retained:
            if not article.entities:
                continue
            seen_entities: set[str] = set()
            for raw in article.entities:
                try:
                    obj = _json.loads(raw)
                    name = obj.get("name", "").strip()
                    if name:
                        key = name.lower()
                        if key not in seen_entities:
                            seen_entities.add(key)
                            entity_to_articles.setdefault(key, []).append(article)
                except (ValueError, TypeError):
                    continue

        # Step 2: Filter entities with enough articles
        viable = {k: v for k, v in entity_to_articles.items() if len(v) >= min_group}

        # Step 3: Rank by count DESC, then name length DESC (more specific = better)
        ranked = sorted(viable.items(), key=lambda x: (-len(x[1]), -len(x[0])))

        # Step 4: Greedy assignment
        assigned_ids: set[UUID] = set()
        entity_groups: list[dict] = []
        cta_count = 0

        for entity_key, articles in ranked:
            if cta_count >= max_ctas:
                break

            available = [a for a in articles if a.id not in assigned_ids]
            if len(available) < min_group:
                continue

            representative = available[0]
            to_hide = available[1:]

            # Collect source info
            source_counts: dict[UUID, dict] = {}
            for a in available:
                sid = a.source_id
                if sid not in source_counts:
                    source_counts[sid] = {
                        "source_id": sid,
                        "source_name": a.source.name,
                        "source_logo_url": a.source.logo_url,
                        "article_count": 0,
                    }
                source_counts[sid]["article_count"] += 1

            sources_list = sorted(
                source_counts.values(), key=lambda x: -x["article_count"]
            )

            # Display label: use original casing from first article's entity
            display_name = entity_key.title()
            for raw in representative.entities:
                try:
                    obj = _json.loads(raw)
                    if obj.get("name", "").lower() == entity_key:
                        display_name = obj["name"]
                        break
                except (ValueError, TypeError):
                    continue

            if len(sources_list) == 1:
                display_label = f"{display_name} \u2014 {len(to_hide)} articles de {sources_list[0]['source_name']}"
            else:
                display_label = f"{display_name} \u2014 {len(to_hide)} articles"

            for a in available:
                assigned_ids.add(a.id)

            entity_groups.append(
                {
                    "entity_name": entity_key,
                    "display_label": display_label,
                    "hidden_count": len(to_hide),
                    "hidden_ids": [a.id for a in to_hide],
                    "representative_id": representative.id,
                    "sources": sources_list,
                }
            )
            cta_count += 1

        # Filter hidden articles
        if entity_groups:
            hidden_ids = set()
            for g in entity_groups:
                hidden_ids.update(g["hidden_ids"])
            retained = [a for a in retained if a.id not in hidden_ids]

        logger.info(
            "entity_regroupement",
            entity_ctas=len(entity_groups),
            assigned=len(assigned_ids),
        )

        return retained, entity_groups, assigned_ids, cta_count

    def _suppress_redundant_source_overflow(self) -> None:
        """Remove source overflow CTAs when their articles are captured by thematic groups."""
        # Collect all source_ids that appear in any thematic group
        thematic_source_ids: set[str] = set()
        all_overflow = (
            getattr(self, "entity_overflow", [])
            + self.keyword_overflow
            + self.topic_overflow
        )
        for info in all_overflow:
            for s in info.get("sources", []):
                sid = s.get("source_id")
                if sid:
                    thematic_source_ids.add(str(sid))

        # Keep source CTA only if the source is NOT covered by any thematic group
        updated = {}
        for source_id, count in self.source_overflow.items():
            if str(source_id) not in thematic_source_ids:
                updated[source_id] = count
        self.source_overflow = updated

    async def _build_carousels(
        self,
        result: list[Content],
        pre_regroup_map: dict[UUID, Content],
        user_id: UUID | None = None,
        max_carousels: int = 6,
    ) -> tuple[list[Content], list[dict]]:
        """
        Promote overflow groups to horizontal carousels.

        Phase A: up to 3 carousels from entity/keyword overflow (hot/favorite/deep).
        Phase B: up to 3 DB-driven carousels (new_source/gems/saved).

        Returns: (filtered_result, carousel_dicts)
        """
        import json as _json

        MIN_CAROUSEL_ITEMS = 3  # Minimum items in carousel (rep + hidden)
        MAX_CAROUSEL_ITEMS = 5
        carousels: list[dict] = []
        promoted_ids: set[UUID] = set()
        used_group_keys: set[str] = set()  # Prevent same group in hot + deep

        # --- hot: entity with highest hidden_count ---
        hot_candidates = sorted(
            self.entity_overflow,
            key=lambda g: g["hidden_count"],
            reverse=True,
        )
        for group in hot_candidates:
            if len(carousels) >= max_carousels:
                break
            # hidden_count + 1 (representative) = total items in carousel
            if group["hidden_count"] + 1 < MIN_CAROUSEL_ITEMS:
                continue
            rep_id = group.get("representative_id")
            if not rep_id or rep_id not in pre_regroup_map:
                continue

            items = [pre_regroup_map[rep_id]]
            for hid in group["hidden_ids"][:MAX_CAROUSEL_ITEMS - 1]:
                if hid in pre_regroup_map:
                    items.append(pre_regroup_map[hid])
            if len(items) < MIN_CAROUSEL_ITEMS:
                continue

            # Extract display name from entity_name
            display_name = group["entity_name"].title()
            for raw in items[0].entities:
                try:
                    obj = _json.loads(raw)
                    if obj.get("name", "").lower() == group["entity_name"]:
                        display_name = obj["name"]
                        break
                except (ValueError, TypeError):
                    continue

            badge = {
                "code": "actu_chaude",
                "label": "Actu chaude",
                "emoji": "\U0001f534",
            }
            carousels.append({
                "carousel_type": "hot",
                "title": f"Actu chaude : {display_name}",
                "emoji": "\U0001f534",
                "position": 5,
                "items": items,
                "badges": [badge] * len(items),
            })
            for item in items:
                promoted_ids.add(item.id)
            used_group_keys.add(f"entity:{group['entity_name']}")
            break  # Only 1 hot carousel

        # --- favorite: keyword_overflow with is_custom_topic == True ---
        for group in self.keyword_overflow:
            if len(carousels) >= max_carousels:
                break
            if not group.get("is_custom_topic"):
                continue
            if group["hidden_count"] + 1 < MIN_CAROUSEL_ITEMS:
                continue
            rep_id = group.get("representative_id")
            if not rep_id or rep_id not in pre_regroup_map:
                continue

            items = [pre_regroup_map[rep_id]]
            for hid in group["hidden_ids"][:MAX_CAROUSEL_ITEMS - 1]:
                if hid in pre_regroup_map:
                    items.append(pre_regroup_map[hid])
            if len(items) < MIN_CAROUSEL_ITEMS:
                continue

            topic_name = group["keyword"]
            badge = {
                "code": "focus_topic",
                "label": topic_name,
                "emoji": "\U0001f3af",
            }
            carousels.append({
                "carousel_type": "favorite",
                "title": f"Focus sur {topic_name}",
                "emoji": "\U0001f3af",
                "position": 10,
                "items": items,
                "badges": [badge] * len(items),
            })
            for item in items:
                promoted_ids.add(item.id)
            used_group_keys.add(f"keyword:{group['filter_keyword']}")
            break  # Only 1 favorite carousel

        # --- deep: overflow group with ≥3 different sources, not already used ---
        deep_candidates = []
        for group in self.entity_overflow:
            key = f"entity:{group['entity_name']}"
            if key in used_group_keys:
                continue
            if group["hidden_count"] + 1 >= MIN_CAROUSEL_ITEMS and len(group.get("sources", [])) >= 3:
                deep_candidates.append(("entity", group))
        for group in self.keyword_overflow:
            key = f"keyword:{group['filter_keyword']}"
            if key in used_group_keys:
                continue
            if group["hidden_count"] + 1 >= MIN_CAROUSEL_ITEMS and len(group.get("sources", [])) >= 3:
                deep_candidates.append(("keyword", group))

        # Sort by source count desc (most diverse first)
        deep_candidates.sort(key=lambda x: len(x[1].get("sources", [])), reverse=True)

        for _kind, group in deep_candidates:
            if len(carousels) >= max_carousels:
                break
            rep_id = group.get("representative_id")
            if not rep_id or rep_id not in pre_regroup_map:
                continue

            items = [pre_regroup_map[rep_id]]
            for hid in group["hidden_ids"][:MAX_CAROUSEL_ITEMS - 1]:
                if hid in pre_regroup_map and hid not in promoted_ids:
                    items.append(pre_regroup_map[hid])
            if len(items) < MIN_CAROUSEL_ITEMS:
                continue

            display_name = group.get("keyword", group.get("entity_name", "")).title()
            # Try to get original casing from entity
            if "entity_name" in group:
                for raw in items[0].entities:
                    try:
                        obj = _json.loads(raw)
                        if obj.get("name", "").lower() == group["entity_name"]:
                            display_name = obj["name"]
                            break
                    except (ValueError, TypeError):
                        continue

            badge = {
                "code": "autre_angle",
                "label": "Autre angle",
                "emoji": "\U0001f50d",
            }
            carousels.append({
                "carousel_type": "deep",
                "title": f"D\u2019autres angles sur {display_name}",
                "emoji": "\U0001f50d",
                "position": 15,
                "items": items,
                "badges": [badge] * len(items),
            })
            for item in items:
                promoted_ids.add(item.id)
            break  # Only 1 deep carousel

        # ================================================================
        # Phase B: DB-driven carousels (require user_id + async queries)
        # ================================================================
        logger.info(
            "carousels_phase_b_start",
            user_id=str(user_id) if user_id else None,
            phase_a_count=len(carousels),
            budget_remaining=max_carousels - len(carousels),
        )
        if user_id is not None:
            # --- new_source: articles from recently added sources ---
            if len(carousels) < max_carousels:
                seven_days_ago = (
                    datetime.datetime.now(datetime.UTC)
                    - datetime.timedelta(days=7)
                )
                new_src_rows = (await self.session.execute(
                    select(UserSource.source_id, Source.name)
                    .join(Source, Source.id == UserSource.source_id)
                    .where(
                        UserSource.user_id == user_id,
                        UserSource.added_at > seven_days_ago,
                    )
                )).all()

                logger.info(
                    "carousel_new_source_query",
                    new_sources_found=len(new_src_rows),
                    source_names=[r.name for r in new_src_rows[:5]],
                )
                if new_src_rows:
                    new_src_ids = [r.source_id for r in new_src_rows]
                    src_name_map = {r.source_id: r.name for r in new_src_rows}

                    new_articles = list((await self.session.scalars(
                        select(Content)
                        .options(selectinload(Content.source))
                        .where(
                            Content.source_id.in_(new_src_ids),
                            Content.published_at > seven_days_ago,
                        )
                        .order_by(Content.published_at.desc())
                        .limit(MAX_CAROUSEL_ITEMS)
                    )).all())

                    items = [
                        a for a in new_articles if a.id not in promoted_ids
                    ][:MAX_CAROUSEL_ITEMS]
                    logger.info(
                        "carousel_new_source_articles",
                        raw_count=len(new_articles),
                        after_exclusion=len(items),
                        min_required=MIN_CAROUSEL_ITEMS,
                    )
                    if len(items) >= MIN_CAROUSEL_ITEMS:
                        first_src_name = src_name_map.get(
                            items[0].source_id, "nouvelle source"
                        )
                        badge = {
                            "code": "new_source",
                            "label": "Nouvelle source",
                            "emoji": "\U0001f195",
                        }
                        carousels.append({
                            "carousel_type": "new_source",
                            "title": f"Récemment ajouté : {first_src_name}",
                            "emoji": "\U0001f195",
                            "position": 3,
                            "items": items,
                            "badges": [badge] * len(items),
                        })
                        for item in items:
                            promoted_ids.add(item.id)

            # --- gems: community favorites (most saved by all users) ---
            if len(carousels) < max_carousels:
                thirty_days_ago = (
                    datetime.datetime.now(datetime.UTC)
                    - datetime.timedelta(days=30)
                )
                exclusion = (
                    Content.id.notin_(promoted_ids) if promoted_ids else True
                )
                gem_rows = (await self.session.execute(
                    select(
                        Content.id,
                        func.count(UserContentStatus.id).label("save_count"),
                    )
                    .join(
                        UserContentStatus,
                        UserContentStatus.content_id == Content.id,
                    )
                    .where(
                        UserContentStatus.is_saved.is_(True),
                        UserContentStatus.saved_at >= thirty_days_ago,
                        exclusion,
                    )
                    .group_by(Content.id)
                    .having(func.count(UserContentStatus.id) >= 1)
                    .order_by(func.count(UserContentStatus.id).desc())
                    .limit(MAX_CAROUSEL_ITEMS)
                )).all()

                logger.info(
                    "carousel_gems_query",
                    gems_found=len(gem_rows),
                    min_required=MIN_CAROUSEL_ITEMS,
                    save_counts=[r.save_count for r in gem_rows[:5]],
                )
                if len(gem_rows) >= MIN_CAROUSEL_ITEMS:
                    gem_ids = [r.id for r in gem_rows]
                    gem_contents = list((await self.session.scalars(
                        select(Content)
                        .options(selectinload(Content.source))
                        .where(Content.id.in_(gem_ids))
                    )).all())
                    # Maintain save_count order
                    id_order = {gid: i for i, gid in enumerate(gem_ids)}
                    items = sorted(
                        gem_contents,
                        key=lambda c: id_order.get(c.id, 99),
                    )

                    badge = {
                        "code": "pepite",
                        "label": "Pépite",
                        "emoji": "\U0001f48e",
                    }
                    carousels.append({
                        "carousel_type": "gems",
                        "title": "Pépites de la communauté",
                        "emoji": "\U0001f48e",
                        "position": 15,
                        "items": items,
                        "badges": [badge] * len(items),
                    })
                    for item in items:
                        promoted_ids.add(item.id)

            # --- saved: user's saved but unconsumed articles ---
            if len(carousels) < max_carousels:
                saved_articles = list((await self.session.scalars(
                    select(Content)
                    .options(selectinload(Content.source))
                    .join(
                        UserContentStatus,
                        UserContentStatus.content_id == Content.id,
                    )
                    .where(
                        UserContentStatus.user_id == user_id,
                        UserContentStatus.is_saved.is_(True),
                        UserContentStatus.status != ContentStatus.CONSUMED,
                    )
                    .order_by(UserContentStatus.created_at.asc())
                    .limit(MAX_CAROUSEL_ITEMS)
                )).all())

                items = [
                    a for a in saved_articles if a.id not in promoted_ids
                ][:MAX_CAROUSEL_ITEMS]
                logger.info(
                    "carousel_saved_query",
                    raw_count=len(saved_articles),
                    after_exclusion=len(items),
                    min_required=MIN_CAROUSEL_ITEMS,
                )
                if len(items) >= MIN_CAROUSEL_ITEMS:
                    badges = []
                    for item in items:
                        ct = item.content_type
                        if ct == ContentType.YOUTUBE:
                            badges.append({
                                "code": "saved_video",
                                "label": "Vidéo sauvegardée",
                                "emoji": "\U0001f4cc",
                            })
                        elif ct == ContentType.PODCAST:
                            badges.append({
                                "code": "saved_audio",
                                "label": "Audio sauvegardé",
                                "emoji": "\U0001f4cc",
                            })
                        else:
                            badges.append({
                                "code": "saved_article",
                                "label": "Article sauvegardé",
                                "emoji": "\U0001f4cc",
                            })

                    carousels.append({
                        "carousel_type": "saved",
                        "title": "Plus tard, c\u2019est maintenant !",
                        "emoji": "\U0001f4cc",
                        "position": 20,
                        "items": items,
                        "badges": badges,
                    })
                    for item in items:
                        promoted_ids.add(item.id)

        # Remove promoted articles from the main feed
        if promoted_ids:
            result = [a for a in result if a.id not in promoted_ids]

        # Convert Content objects to serializable dicts for CarouselInfo
        carousel_dicts = []
        for c in carousels:
            carousel_dicts.append({
                "carousel_type": c["carousel_type"],
                "title": c["title"],
                "emoji": c["emoji"],
                "position": c["position"],
                "items": c["items"],  # Content objects — router will serialize via Pydantic
                "badges": c["badges"],
            })

        logger.info(
            "carousels_built",
            count=len(carousel_dicts),
            types=[c["carousel_type"] for c in carousel_dicts],
        )

        return result, carousel_dicts

    @staticmethod
    def _apply_source_safety_net(
        articles: list[Content],
    ) -> tuple[list[Content], dict[UUID, int]]:
        """Force-group 3+ consecutive articles from same source into a source CTA."""
        if len(articles) < 3:
            return articles, {}

        forced_overflow: dict[UUID, int] = {}
        to_remove: set[UUID] = set()

        i = 0
        while i < len(articles):
            # Find run of same source
            j = i + 1
            while j < len(articles) and articles[j].source_id == articles[i].source_id:
                j += 1
            run_length = j - i
            if run_length >= 3:
                # Keep first, hide the rest
                for k in range(i + 1, j):
                    to_remove.add(articles[k].id)
                sid = articles[i].source_id
                forced_overflow[sid] = forced_overflow.get(sid, 0) + (run_length - 1)
            i = j

        if to_remove:
            articles = [a for a in articles if a.id not in to_remove]

        return articles, forced_overflow

    @staticmethod
    def _extract_keywords(
        title: str, stop_words: frozenset[str], min_length: int
    ) -> list[str]:
        """Extract meaningful keywords from an article title."""
        tokens = re.findall(r"[a-zàâäéèêëïîôùûüÿçœæ\-]+", title.lower())

        # Normalize accented chars for stop word matching, keep original for display
        # e.g. "après" → stripped "apres" for lookup, but "après" returned as keyword
        def _strip_accents(t: str) -> str:
            return "".join(
                c
                for c in unicodedata.normalize("NFD", t)
                if unicodedata.category(c) != "Mn"
            )

        return [
            t
            for t in tokens
            if len(t) >= min_length and _strip_accents(t) not in stop_words
        ]

    @staticmethod
    def _apply_keyword_regroupement(
        retained: list[Content],
        user_custom_topics: list,
        _user_subtopic_weights: dict[str, float],
        target_slots: int = 20,
        pre_assigned_ids: set[UUID] | None = None,
        max_ctas: int | None = None,
    ) -> tuple[list[Content], list[dict], list[dict]]:
        """
        Keyword-based feed regroupement replacing topic regroupement.

        Mines keywords from article titles to create granular CTA chips
        like "Trump — 4 articles" instead of broad "Sport — 150 articles".

        Returns: (compressed_articles, keyword_overflow_info, topic_overflow_fallback)
        """
        from app.services.recommendation.french_stopwords import FRENCH_STOP_WORDS

        min_kw = ScoringWeights.MIN_FOR_KEYWORD_GROUPING
        if len(retained) < 15:
            min_kw = 2
        kw_min_len = ScoringWeights.KEYWORD_MIN_LENGTH
        max_ctas = max_ctas if max_ctas is not None else ScoringWeights.MAX_TOTAL_CTAS

        # --- Step 1: Build keyword index from titles ---
        keyword_to_articles: dict[str, list[Content]] = {}
        for article in retained:
            keywords = RecommendationService._extract_keywords(
                article.title, FRENCH_STOP_WORDS, kw_min_len
            )
            for kw in keywords:
                keyword_to_articles.setdefault(kw, []).append(article)

        # --- Step 2: Filter keywords with enough articles ---
        viable_keywords = {
            kw: arts for kw, arts in keyword_to_articles.items() if len(arts) >= min_kw
        }

        # --- Step 3: Rank by count DESC, then length DESC (longer = more specific) ---
        ranked_keywords = sorted(
            viable_keywords.items(), key=lambda x: (-len(x[1]), -len(x[0]))
        )

        # --- Step 4: Check custom topic lens ---
        custom_topic_keyword_map: dict[str, str] = {}
        for ct in user_custom_topics:
            if hasattr(ct, "keywords") and ct.keywords:
                for k in ct.keywords:
                    custom_topic_keyword_map[k.lower()] = ct.topic_name

        # --- Step 5: Greedy assignment (one article = one group max) ---
        assigned_ids: set[UUID] = set(pre_assigned_ids) if pre_assigned_ids else set()
        keyword_groups: list[dict] = []
        cta_count = 0

        for keyword, articles in ranked_keywords:
            if cta_count >= max_ctas:
                break

            # Filter out already-assigned articles
            available = [a for a in articles if a.id not in assigned_ids]
            if len(available) < min_kw:
                continue

            # Keep first article as representative, hide the rest
            to_hide = available[1:]

            # Collect source info for multi-source display
            source_counts: dict[UUID, dict] = {}
            for a in available:
                sid = a.source_id
                if sid not in source_counts:
                    source_counts[sid] = {
                        "source_id": sid,
                        "source_name": a.source.name,
                        "source_logo_url": a.source.logo_url,
                        "article_count": 0,
                    }
                source_counts[sid]["article_count"] += 1

            sources_list = sorted(
                source_counts.values(), key=lambda x: -x["article_count"]
            )

            # Build display label
            display_keyword = custom_topic_keyword_map.get(keyword, keyword.title())
            is_custom = keyword in custom_topic_keyword_map

            if len(sources_list) == 1:
                display_label = f"{display_keyword} \u2014 {len(to_hide)} articles de {sources_list[0]['source_name']}"
            else:
                display_label = f"{display_keyword} \u2014 {len(to_hide)} articles"

            # Mark all articles in this group as assigned
            for a in available:
                assigned_ids.add(a.id)

            keyword_groups.append(
                {
                    "keyword": display_keyword,
                    "filter_keyword": keyword,
                    "display_label": display_label,
                    "hidden_count": len(to_hide),
                    "hidden_ids": [a.id for a in to_hide],
                    "representative_id": available[0].id,
                    "sources": sources_list,
                    "is_custom_topic": is_custom,
                }
            )
            cta_count += 1

        # --- Step 6: Fallback — unassigned articles through topic slug grouping ---
        THEME_LABELS = {
            "tech": "Tech & Innovation",
            "society": "Société",
            "environment": "Environnement",
            "economy": "Économie",
            "politics": "Politique",
            "culture": "Culture & Idées",
            "science": "Sciences",
            "international": "Géopolitique",
            "geopolitics": "Géopolitique",
            "society_climate": "Société",
            "culture_ideas": "Culture & Idées",
        }

        topic_overflow_info: list[dict] = []
        ids_to_hide_kw: set[UUID] = set()

        for group in keyword_groups:
            ids_to_hide_kw.update(group["hidden_ids"])

        # Topic slug fallback for remaining articles
        if cta_count < max_ctas:
            unassigned = [a for a in retained if a.id not in assigned_ids]
            by_topic: dict[str, list[Content]] = {}
            for article in unassigned:
                if article.topics:
                    slug = article.topics[0].lower().strip()
                    by_topic.setdefault(slug, []).append(article)

            min_topic = ScoringWeights.MIN_FOR_TOPIC_GROUPING
            min_theme = ScoringWeights.MIN_FOR_THEME_GROUPING
            for slug, arts in sorted(by_topic.items(), key=lambda x: -len(x[1])):
                if cta_count >= max_ctas:
                    break
                is_theme = slug in THEME_LABELS
                min_required = min_theme if is_theme else min_topic
                if len(arts) < min_required:
                    continue

                to_hide = arts[1:]
                if len(to_hide) < 2:
                    continue

                ids_to_hide_kw.update(a.id for a in to_hide)
                # Collect unique sources from all articles in the group
                seen_src: set[str] = set()
                sources_list: list[dict] = []
                for a in arts:
                    sid = str(a.source_id)
                    if sid not in seen_src and a.source:
                        seen_src.add(sid)
                        sources_list.append(
                            {
                                "source_id": a.source_id,
                                "source_name": a.source.name,
                                "source_logo_url": a.source.logo_url,
                                "article_count": sum(
                                    1 for x in arts if str(x.source_id) == sid
                                ),
                            }
                        )
                # Sort: sources with logos first
                sources_list.sort(key=lambda s: 0 if s["source_logo_url"] else 1)
                topic_overflow_info.append(
                    {
                        "group_type": "theme" if is_theme else "topic",
                        "group_key": slug,
                        "group_label": THEME_LABELS.get(
                            slug, slug.replace("-", " ").title()
                        ),
                        "hidden_count": len(to_hide),
                        "hidden_ids": [a.id for a in to_hide],
                        "sources": sources_list,
                    }
                )
                cta_count += 1

        # --- Step 7: Filter hidden articles and trim to target ---
        if ids_to_hide_kw:
            retained = [a for a in retained if a.id not in ids_to_hide_kw]

        retained = retained[:target_slots]

        logger.info(
            "keyword_regroupement",
            keyword_ctas=len(keyword_groups),
            topic_fallback_ctas=len(topic_overflow_info),
            hidden=len(ids_to_hide_kw),
            final_count=len(retained),
        )

        return retained, keyword_groups, topic_overflow_info

    def _hydrate_legacy_reasons(
        self, result: list[Content], context: ScoringContext
    ) -> None:
        """Legacy reason hydration (v1 layers)."""
        THEME_TRANSLATIONS = {
            "tech": "Tech & Innovation",
            "society": "Société",
            "environment": "Environnement",
            "economy": "Économie",
            "politics": "Politique",
            "culture": "Culture & Idées",
            "science": "Sciences",
            "international": "Géopolitique",
            "geopolitics": "Géopolitique",
            "society_climate": "Société",
            "culture_ideas": "Culture & Idées",
        }

        SUBTOPIC_TRANSLATIONS = {
            "ai": "IA",
            "llm": "LLM",
            "crypto": "Crypto",
            "web3": "Web3",
            "space": "Spatial",
            "biotech": "Biotech",
            "quantum": "Quantique",
            "cybersecurity": "Cybersécurité",
            "robotics": "Robotique",
            "gaming": "Gaming",
            "cleantech": "Cleantech",
            "data-privacy": "Données",
            "social-justice": "Justice sociale",
            "feminism": "Féminisme",
            "lgbtq": "LGBTQ+",
            "immigration": "Immigration",
            "health": "Santé",
            "education": "Éducation",
            "urbanism": "Urbanisme",
            "housing": "Logement",
            "work-reform": "Travail",
            "justice-system": "Justice",
            "climate": "Climat",
            "biodiversity": "Biodiversité",
            "energy-transition": "Transition énergétique",
            "pollution": "Pollution",
            "circular-economy": "Économie circulaire",
            "agriculture": "Agriculture",
            "oceans": "Océans",
            "forests": "Forêts",
            "macro": "Macro-économie",
            "finance": "Finance",
            "startups": "Startups",
            "venture-capital": "VC",
            "labor-market": "Emploi",
            "inflation": "Inflation",
            "trade": "Commerce",
            "taxation": "Fiscalité",
            "elections": "Élections",
            "institutions": "Institutions",
            "local-politics": "Politique locale",
            "activism": "Activisme",
            "democracy": "Démocratie",
            "philosophy": "Philosophie",
            "art": "Art",
            "cinema": "Cinéma",
            "media-critics": "Critique des médias",
            "fundamental-research": "Recherche",
            "applied-science": "Sciences appliquées",
            "geopolitics": "Géopolitique",
        }

        def _get_theme_label(raw_theme: str) -> str:
            return THEME_TRANSLATIONS.get(
                raw_theme.lower().strip(), raw_theme.capitalize()
            )

        def _get_subtopic_label(slug: str) -> str:
            return SUBTOPIC_TRANSLATIONS.get(slug.lower().strip(), slug.capitalize())

        def _reason_to_label(reason: dict) -> str:
            layer = reason["layer"]
            details = reason["details"]
            if layer == "core_v1":
                if "Thème" in details:
                    try:
                        theme_slug = details.split(": ")[1]
                        return f"Thème : {_get_theme_label(theme_slug)}"
                    except Exception:
                        return "Thème matché"
                elif "confiance" in details.lower():
                    return "Source de confiance"
                elif "personnalisée" in details.lower():
                    return "Ta source personnalisée"
                elif "Affinité" in details or "affinit" in details.lower():
                    return "Source appréciée"
                elif "favorite" in details.lower():
                    return "Source favorite"
                elif "réduite" in details.lower():
                    return "Source réduite"
                else:
                    return details
            elif layer == "article_topic":
                try:
                    raw = details.split(": ")[1].replace(" (précis)", "")
                    slugs = [t.strip() for t in raw.split(",")]
                    labels = [_get_subtopic_label(s) for s in slugs[:2]]
                    return f"Sous-thèmes : {', '.join(labels)}"
                except Exception:
                    return "Sous-thèmes matchés"
            elif layer == "static_prefs":
                if "Recent" in details:
                    return "Très récent"
                elif "format" in details.lower():
                    return "Format préféré"
                else:
                    return "Préférence"
            elif layer == "behavioral":
                if "High interest" in details:
                    try:
                        theme_slug = details.split(": ")[1].split(" ")[0]
                        return f"Engagement élevé : {_get_theme_label(theme_slug)}"
                    except Exception:
                        return "Engagement élevé"
                else:
                    return "Engagement"
            elif layer == "quality":
                if "qualitative" in details.lower():
                    return "Source qualitative"
                elif "Low" in details:
                    return "Fiabilité basse"
                else:
                    return "Qualité source"
            elif layer == "visual":
                return "Aperçu disponible"
            elif layer == "content_quality":
                if "Rich" in details or "full" in details.lower():
                    return "Lecture complète dans Facteur"
                elif "Partial" in details or "partial" in details.lower():
                    return "Lecture partielle disponible"
                else:
                    return details
            elif layer == "user_custom_topic":
                try:
                    topic_name = details.split(": ")[1].split(" (")[0]
                    return f"Votre sujet : {topic_name}"
                except Exception:
                    return "Sujet personnalisé"
            elif layer in ("personalization", "impression"):
                return details
            else:
                return details

        for content in result:
            reasons_list = context.reasons.get(content.id, [])
            if not reasons_list:
                continue

            breakdown = []
            score_total = 0.0

            for reason in reasons_list:
                try:
                    pts = reason.get("score_contribution", 0.0)
                    score_total += pts
                    breakdown.append(
                        ScoreContribution(
                            label=_reason_to_label(reason),
                            points=pts,
                            is_positive=(pts >= 0),
                        )
                    )
                except Exception as e:
                    logger.warning(
                        "reason_breakdown_failed",
                        error=str(e),
                        content_id=str(content.id),
                    )
                    continue

            breakdown.sort(key=lambda x: abs(x.points), reverse=True)

            reasons_list.sort(
                key=lambda x: (
                    x.get("layer") == "article_topic",
                    x.get("score_contribution", 0.0),
                ),
                reverse=True,
            )

            label = "Recommandé pour vous"
            if reasons_list:
                top = reasons_list[0]
                try:
                    layer = top.get("layer")
                    details = top.get("details", "")
                    if layer == "core_v1":
                        if "Thème" in details:
                            try:
                                theme_slug = details.split(": ")[1]
                                label = f"Vos intérêts : {_get_theme_label(theme_slug)}"
                            except Exception:
                                label = "Vos intérêts"
                        elif "confiance" in details.lower():
                            label = "Source suivie"
                        elif "affinit" in details.lower():
                            label = "Source appréciée"
                    elif layer == "article_topic":
                        try:
                            raw_part = (
                                details.split(": ")[1]
                                .split(" [")[0]
                                .replace(" (précis)", "")
                            )
                            topic_slugs = [t.strip() for t in raw_part.split(",")]
                            topic_labels = [
                                _get_subtopic_label(t) for t in topic_slugs[:2]
                            ]
                            if "[liked:" in details:
                                label = f"Renforcé par vos j'aime : {', '.join(topic_labels)}"
                            else:
                                label = (
                                    f"Vos centres d'intérêt : {', '.join(topic_labels)}"
                                )
                        except Exception:
                            label = "Vos centres d'intérêt"
                    elif layer == "static_prefs":
                        if "Recent" in details:
                            label = "Très récent"
                        elif "format" in details or "Pref" in details:
                            label = "Format préféré"
                    elif layer == "behavioral":
                        if "High interest" in details:
                            try:
                                theme_slug = details.split(": ")[1].split(" ")[0]
                                label = f"Sujet passionnant : {_get_theme_label(theme_slug)}"
                            except Exception:
                                label = "Sujet passionnant"
                    elif layer == "quality":
                        if "qualitative" in details.lower():
                            label = "Source de Confiance"
                        elif "Low" in details:
                            label = "Source Controversée"
                    elif layer == "visual":
                        label = "Aperçu disponible"
                except Exception as e:
                    logger.warning(
                        "top_reason_label_failed",
                        error=str(e),
                        content_id=str(content.id),
                    )

            content.recommendation_reason = RecommendationReason(
                label=label, score_total=score_total, breakdown=breakdown
            )

    async def _get_candidates(
        self,
        user_id: UUID,
        limit_candidates: int,
        content_type: str | None = None,
        mode: FeedFilterMode | None = None,
        followed_source_ids: set[UUID] | None = None,
        muted_sources: set[UUID] = None,
        muted_themes: set[str] = None,
        muted_topics: set[str] = None,
        muted_content_types: set[str] = None,
        digest_content_ids: list[UUID] = None,
        theme: str | None = None,
        hide_paid_content: bool = True,
        subscribed_source_ids: set[UUID] = None,
        source_id: UUID | None = None,
        topic: str | None = None,
        entity: str | None = None,
        keyword: str | None = None,
        serein: bool = False,
    ) -> list[Content]:
        """Récupère les N contenus les plus récents que l'utilisateur n'a pas encore vus/consommés et qui ne sont pas masqués."""
        from sqlalchemy import and_, or_

        # Sanitize inputs to prevent SQL Tri-state logic issues with "NOT IN (NULL, ...)"
        # If a set contains None, "NOT IN" evaluates to NULL (unknown) for ALL rows, causing empty results.
        if muted_sources:
            muted_sources = {s for s in muted_sources if s is not None}

        if muted_themes:
            # Filter out None and empty strings
            muted_themes = {t for t in muted_themes if t}

        if muted_topics:
            # Filter out None and empty strings
            muted_topics = {t for t in muted_topics if t}

        # Candidates to EXCLUDE:
        # When user explicitly filters by source or theme, only exclude hidden
        # articles — they want to browse ALL content for that source/theme.
        # Otherwise, exclude hidden + saved + seen + consumed (default feed).
        from sqlalchemy import exists

        explicit_filter = (
            source_id is not None
            or theme is not None
            or topic is not None
            or entity is not None
            or keyword is not None
        )

        if explicit_filter:
            # Relaxed: only exclude explicitly hidden articles
            exists_stmt = exists().where(
                UserContentStatus.content_id == Content.id,
                UserContentStatus.user_id == user_id,
                UserContentStatus.is_hidden,
            )
        else:
            # Default feed: exclude hidden, saved, seen, consumed
            exists_stmt = exists().where(
                UserContentStatus.content_id == Content.id,
                UserContentStatus.user_id == user_id,
                or_(
                    UserContentStatus.is_hidden,
                    UserContentStatus.is_saved,
                    UserContentStatus.status.in_(
                        [ContentStatus.SEEN, ContentStatus.CONSUMED]
                    ),
                ),
            )

        query = (
            select(Content)
            .join(Content.source)  # Join needed for all mode filters
            .options(selectinload(Content.source))
            .where(~exists_stmt)
        )

        # Story 10.20: Exclude today's digest articles from feed
        if digest_content_ids:
            query = query.where(Content.id.notin_(digest_content_ids))

        # Debug logging for feed source filtering
        logger.info(
            "feed_source_filter",
            user_id=str(user_id),
            followed_source_count=len(followed_source_ids)
            if followed_source_ids
            else 0,
            followed_source_ids=[str(s) for s in list(followed_source_ids)[:10]]
            if followed_source_ids
            else [],
        )

        # Base source filter
        # source_id: show only articles from this specific source
        # theme/topic/entity: show curated sources (broader discovery)
        # followed_source_ids: followed sources only (no curated enrichment)
        _use_two_phase = False
        if source_id:
            query = query.where(Content.source_id == source_id)
        elif theme or topic or entity:
            if followed_source_ids:
                query = query.where(
                    or_(
                        and_(Source.is_curated, Source.source_tier != "deep"),
                        Source.id.in_(list(followed_source_ids)),
                    )
                )
            else:
                query = query.where(Source.is_curated, Source.source_tier != "deep")
        elif followed_source_ids:
            # Don't apply source filter yet — two-phase fetch after all filters
            _use_two_phase = True
        else:
            query = query.where(Source.is_curated, Source.source_tier != "deep")

        # Apply Personalization Filters (Mutes)
        if muted_sources:
            query = query.where(Source.id.notin_(list(muted_sources)))

        if muted_themes:
            # SQL IN operator is case-sensitive, but we stored lowercase slugs.
            # Ensure Source.theme is compared correctly (assuming themes are lowercase in DB or we use lower())
            query = query.where(~Source.theme.in_(list(muted_themes)))

        if muted_topics:
            # Filter based on Content.topics (Array overlap)
            # Postgres operator && (overlap). Negated with ~
            # Fix 500: Handle NULL Content.topics explicitly
            query = query.where(
                or_(
                    Content.topics.is_(None),
                    ~Content.topics.overlap(list(muted_topics)),
                )
            )

        # Apply content_type filter if provided (positive filter)
        if content_type:
            query = query.where(Content.content_type == content_type)

        # Apply muted content types filter (negative filter from personalization)
        if muted_content_types:
            query = query.where(Content.content_type.notin_(list(muted_content_types)))

        # Apply paywall filter (is_not(True) handles NULL rows)
        # Allow paid content from subscribed sources
        if hide_paid_content:
            if subscribed_source_ids:
                query = query.where(
                    or_(
                        Content.is_paid.is_not(True),
                        Content.source_id.in_(list(subscribed_source_ids)),
                    )
                )
            else:
                query = query.where(Content.is_paid.is_not(True))

        # Apply serein content filter (orthogonal to mode — filters anxiety content)
        if serein and not source_id:
            query = apply_serein_filter(query)

        # Apply Mode Logic (skip when filtering by specific source)
        if mode and not source_id:
            if mode == FeedFilterMode.DEEP_DIVE:
                # Mode "Grand Format" : Contenus > 10min (videos, podcasts, OU articles longs)
                # Note: 45 videos ont duration_seconds=NULL en base. On les inclut par défaut.
                query = query.where(
                    or_(
                        # Videos et Podcasts: Durée inconnue (NULL) ou > 10 min
                        and_(
                            or_(
                                Content.duration_seconds > 600,
                                Content.duration_seconds is None,
                            ),
                            Content.content_type.in_(
                                [ContentType.PODCAST, ContentType.YOUTUBE]
                            ),
                        ),
                        # Articles longs (estimation basée sur description length comme proxy)
                        # TODO: Ajouter un vrai champ reading_time_minutes à Content
                        and_(
                            Content.content_type == ContentType.ARTICLE,
                            func.length(Content.description)
                            > 2000,  # ~10 min de lecture
                        ),
                    )
                )

            elif mode == FeedFilterMode.PERSPECTIVES:
                # Mode "Angle Mort" : Perspective swap — via filter_presets partagés
                user_bias_stance = await calculate_user_bias(self.session, user_id)
                target_bias = get_opposing_biases(user_bias_stance)

                query = query.where(Source.bias_stance.in_(target_bias))

        # Apply theme filter (Story 2 - Feed par thème, skip when source filter active)
        if theme and not source_id:
            query = apply_theme_focus_filter(query, theme)

        # Apply topic filter (granular ML topic, e.g. 'ai', 'startups')
        if topic and not source_id:
            query = apply_topic_filter(query, topic)

        # Apply entity filter (entity name within JSON-encoded entity array)
        if entity and not source_id:
            query = apply_entity_filter(query, entity)

        # Apply keyword filter (title ILIKE match for keyword overflow chip taps)
        if keyword and not source_id:
            query = apply_keyword_filter(query, keyword)

        if _use_two_phase:
            # Followed sources only — no curated enrichment in default feed.
            # Curated enrichment is reserved for digest (digest_selector.py).
            user_query = query.where(Source.id.in_(list(followed_source_ids)))
            user_query = user_query.order_by(Content.published_at.desc()).limit(
                limit_candidates
            )
            user_result = await self.session.scalars(user_query)
            candidates_list = list(user_result.all())

            logger.info(
                "feed_candidates_followed_only",
                user_id=str(user_id),
                followed_source_count=len(followed_source_ids),
                candidates=len(candidates_list),
            )
        else:
            query = query.order_by(Content.published_at.desc()).limit(limit_candidates)
            candidates = await self.session.scalars(query)
            candidates_list = list(candidates.all())

        # Debug logging for mode filters
        if mode:
            logger.info(
                "candidates_after_mode_filter",
                mode=mode.value,
                count=len(candidates_list),
                sample_sources=[
                    c.source.name if c.source else "N/A" for c in candidates_list[:5]
                ],
            )

        return candidates_list

    def _source_affinity_stmt(self, user_id: UUID):
        """Build the source affinity query statement (reusable for parallel execution)."""
        from sqlalchemy import case

        return (
            select(
                Content.source_id,
                func.sum(
                    case((UserContentStatus.is_liked, 3), else_=0)
                    + case((UserContentStatus.is_saved, 2), else_=0)
                    + case(
                        (UserContentStatus.status == ContentStatus.CONSUMED, 1), else_=0
                    )
                ).label("raw_score"),
            )
            .join(Content, UserContentStatus.content_id == Content.id)
            .where(UserContentStatus.user_id == user_id)
            .group_by(Content.source_id)
        )

    @staticmethod
    def _normalize_affinity(rows) -> dict[UUID, float]:
        """Normalize source affinity rows to 0.0-1.0 range."""
        if not rows:
            return {}
        scores = {
            row.source_id: float(row.raw_score) for row in rows if row.raw_score > 0
        }
        if not scores:
            return {}
        max_score = max(scores.values())
        if max_score == 0:
            return {}
        return {sid: score / max_score for sid, score in scores.items()}

    async def _compute_source_affinity(self, user_id: UUID) -> dict[UUID, float]:
        """Compute source affinity scores from past interactions.

        Score brut = likes * 3 + saves * 2 + consumed * 1
        Normalisé en 0.0-1.0 (min-max sur les sources de l'utilisateur).
        """
        rows = (await self.session.execute(self._source_affinity_stmt(user_id))).all()
        return self._normalize_affinity(rows)

    async def fetch_impression_data(
        self, user_id: UUID, candidates: list[Content]
    ) -> dict[UUID, tuple]:
        """Fetch impression timestamps for candidates (Feed Refresh).

        Returns {content_id: (last_impressed_at, manually_impressed)} for
        candidates that have been impressed at least once.
        """
        candidate_ids = [c.id for c in candidates]
        if not candidate_ids:
            return {}

        stmt = select(
            UserContentStatus.content_id,
            UserContentStatus.last_impressed_at,
            UserContentStatus.manually_impressed,
        ).where(
            UserContentStatus.user_id == user_id,
            UserContentStatus.content_id.in_(candidate_ids),
            UserContentStatus.last_impressed_at.isnot(None),
        )

        rows = (await self.session.execute(stmt)).all()
        return {
            row.content_id: (row.last_impressed_at, row.manually_impressed)
            for row in rows
        }

    # _calculate_user_bias and _get_opposing_biases moved to
    # app.services.recommendation.filter_presets (shared with DigestSelector)

    @staticmethod
    def build_clusters(
        feed_items: list[Content],
        user_custom_topics: list,
        min_articles: int = 3,
        max_clusters: int = 3,
    ) -> tuple[list[Content], list[dict]]:
        """Build clusters from feed items based on user's custom topics.

        Groups articles by matching custom topic slug_parent. If a group
        has >= min_articles, keeps only the first (best-scored) as representative
        and removes the rest from the feed.

        Args:
            feed_items: Scored and sorted feed items.
            user_custom_topics: User's custom topic profiles.
            min_articles: Minimum articles to form a cluster.
            max_clusters: Maximum clusters to return.

        Returns:
            (filtered_items, clusters) where filtered_items has hidden articles
            removed and clusters contains metadata for the frontend.
        """
        if not user_custom_topics or not feed_items:
            return feed_items, []

        # Build a set of followed slug_parents with their names
        topic_map = {t.slug_parent: t.topic_name for t in user_custom_topics}

        # Group articles by matching custom topic slug
        from collections import defaultdict

        topic_articles: dict[str, list[Content]] = defaultdict(list)

        for article in feed_items:
            if not article.topics:
                continue
            article_topics = {t.lower().strip() for t in article.topics if t}
            for slug in topic_map:
                if slug in article_topics:
                    topic_articles[slug].append(article)
                    break  # Only assign to first matching topic

        # Build clusters for topics with enough articles
        clusters = []
        hidden_ids = set()

        for slug, articles in sorted(
            topic_articles.items(), key=lambda x: len(x[1]), reverse=True
        ):
            if len(articles) < min_articles:
                continue
            if len(clusters) >= max_clusters:
                break

            representative = articles[0]  # Best scored (list is already sorted)
            others = articles[1:]

            # Collect unique sources from all articles in the cluster
            seen_src: set[str] = set()
            sources_list: list[dict] = []
            for a in articles:
                sid = str(a.source_id)
                if sid not in seen_src and a.source:
                    seen_src.add(sid)
                    sources_list.append(
                        {
                            "source_id": a.source_id,
                            "source_name": a.source.name,
                            "source_logo_url": a.source.logo_url,
                            "article_count": sum(
                                1 for x in articles if str(x.source_id) == sid
                            ),
                        }
                    )
            # Sort: sources with logos first
            sources_list.sort(key=lambda s: 0 if s["source_logo_url"] else 1)

            clusters.append(
                {
                    "topic_slug": slug,
                    "topic_name": topic_map[slug],
                    "representative_id": representative.id,
                    "hidden_count": len(others),
                    "hidden_ids": [a.id for a in others],
                    "sources": sources_list,
                }
            )

            hidden_ids.update(a.id for a in others)

        # Remove hidden articles from feed items
        if hidden_ids:
            filtered_items = [a for a in feed_items if a.id not in hidden_ids]
        else:
            filtered_items = feed_items

        return filtered_items, clusters
