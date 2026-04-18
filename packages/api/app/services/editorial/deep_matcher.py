"""ÉTAPE 3B — Deep source article matching.

Two-pass strategy:
  Pass 1: Jaccard pre-filter (no LLM) → top N candidates
  Pass 2: LLM evaluates candidates and picks best match.
          If the LLM returns `selected_index: null`, the topic ends with
          no deep article — there is no deterministic Pass 3 fallback.
          Better a missing "Pas de recul" than a hors-sujet one.

Topics with `deep_angle` null/empty are skipped entirely (people,
faits divers, actualité purement événementielle).

No time limit on deep articles (can be months old).
"""

from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager

import structlog
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker
from sqlalchemy.orm import selectinload

from app.models.content import Content
from app.models.source import Source
from app.services.briefing.importance_detector import ImportanceDetector
from app.services.editorial.config import EditorialConfig
from app.services.editorial.llm_client import EditorialLLMClient
from app.services.editorial.schemas import MatchedDeepArticle, SelectedTopic

logger = structlog.get_logger()


class DeepMatcher:
    """Matches editorial topics to deep source articles."""

    def __init__(
        self,
        session: AsyncSession,
        llm: EditorialLLMClient,
        config: EditorialConfig,
        session_maker: async_sessionmaker[AsyncSession] | None = None,
    ) -> None:
        # Préférer `session_maker` pour ouvrir des sessions courtes autour
        # de chaque opération DB. Cf. docs/bugs/bug-infinite-load-requests.md
        # (P1). `session` est conservé pour compat ascendante (tests, appels
        # legacy) ; il est utilisé uniquement si `session_maker` est None.
        self._session = session
        self._session_maker = session_maker
        self._llm = llm
        self._config = config
        self._detector = ImportanceDetector()

    @asynccontextmanager
    async def _short_session(self):
        """Open a short-lived session, or fall back to the injected one."""
        if self._session_maker is None:
            yield self._session
            return
        async with self._session_maker() as session:
            try:
                yield session
            except Exception:
                await session.rollback()
                raise

    async def match_for_topics(
        self,
        selected_topics: list[SelectedTopic],
        cluster_entities: dict[str, set[str]] | None = None,
    ) -> dict[str, MatchedDeepArticle | None]:
        """Match deep articles for all topics.

        Args:
            selected_topics: Topics to match.
            cluster_entities: Optional dict mapping topic_id to entity names
                extracted from cluster contents (boosts matching accuracy).

        Returns:
            Dict mapping topic_id to MatchedDeepArticle or None.
        """
        _cluster_entities = cluster_entities or {}

        # Load all deep source articles once
        deep_articles = await self._load_deep_articles()
        if not deep_articles:
            logger.warning("deep_matcher.no_deep_articles")
            return {t.topic_id: None for t in selected_topics}

        logger.info("deep_matcher.pool_loaded", count=len(deep_articles))

        # Skip topics flagged as having no meaningful deep angle — we refuse
        # to force a "Pas de recul" on purely eventful / people / faits-divers
        # subjects. Curation can set deep_angle=None to signal this. Skipped
        # topics don't trigger any LLM call (no query expansion either).
        matchable_topics = [t for t in selected_topics if (t.deep_angle or "").strip()]
        skipped = [t for t in selected_topics if not (t.deep_angle or "").strip()]
        for topic in skipped:
            logger.info(
                "deep_matcher.skipped_no_angle",
                topic_id=topic.topic_id,
                label=topic.label,
            )

        # Query expansion: enrich search tokens via small LLM (parallel)
        expanded_tokens: dict[str, set[str]] = {}
        if self._llm.is_ready and matchable_topics:
            expansion_tasks = [self._expand_query(t) for t in matchable_topics]
            expansion_results = await asyncio.gather(
                *expansion_tasks, return_exceptions=True
            )
            for topic, result in zip(matchable_topics, expansion_results, strict=False):
                if isinstance(result, set):
                    expanded_tokens[topic.topic_id] = result
                    logger.info(
                        "deep_matcher.query_expanded",
                        topic_id=topic.topic_id,
                        extra_tokens=len(result),
                    )
                else:
                    logger.warning(
                        "deep_matcher.expansion_failed",
                        topic_id=topic.topic_id,
                        error=str(result),
                    )

        # Pass 1: Pre-filter per topic
        prefilter_limit = self._config.pipeline.deep_candidates_prefilter
        threshold = self._config.pipeline.deep_jaccard_threshold
        candidates_per_topic: dict[str, list[tuple[Content, float]]] = {}

        for topic in matchable_topics:
            # Boost prefilter for "à la une" topic: wider net, lower threshold
            topic_limit = prefilter_limit * 2 if topic.is_a_la_une else prefilter_limit
            topic_threshold = threshold / 2 if topic.is_a_la_une else threshold
            candidates = self._prefilter(
                topic=topic,
                articles=deep_articles,
                limit=topic_limit,
                threshold=topic_threshold,
                extra_tokens=expanded_tokens.get(topic.topic_id, set()),
                cluster_entities=_cluster_entities.get(topic.topic_id),
            )
            candidates_per_topic[topic.topic_id] = candidates
            logger.info(
                "deep_matcher.prefilter",
                topic_id=topic.topic_id,
                candidates=len(candidates),
            )

        # Pass 2: LLM evaluation (parallel) — LLM rejection is final, no
        # broader fallback. Better no "Pas de recul" than a hors-sujet one.
        if self._llm.is_ready:
            tasks = [
                self._llm_evaluate(topic, candidates_per_topic.get(topic.topic_id, []))
                for topic in matchable_topics
            ]
            results = await asyncio.gather(*tasks, return_exceptions=True)

            matches: dict[str, MatchedDeepArticle | None] = {
                t.topic_id: None for t in skipped
            }
            llm_rejected = 0
            for topic, result in zip(matchable_topics, results, strict=False):
                if isinstance(result, Exception):
                    logger.error(
                        "deep_matcher.llm_error",
                        topic_id=topic.topic_id,
                        error=str(result),
                    )
                    # Exception ≠ rejection: fall back to top Jaccard.
                    matches[topic.topic_id] = self._fallback_pick(
                        candidates_per_topic.get(topic.topic_id, [])
                    )
                else:
                    matches[topic.topic_id] = result
                    if result is None:
                        llm_rejected += 1

            logger.info(
                "deep_matcher.llm_rejections",
                rejected=llm_rejected,
                matched=sum(1 for v in matches.values() if v is not None),
                skipped_no_angle=len(skipped),
                total=len(selected_topics),
            )

            return matches

        # No LLM: use Jaccard fallback for all matchable topics
        logger.info("deep_matcher.no_llm_fallback_all")
        fallback_matches: dict[str, MatchedDeepArticle | None] = {
            t.topic_id: None for t in skipped
        }
        for topic in matchable_topics:
            fallback_matches[topic.topic_id] = self._fallback_pick(
                candidates_per_topic.get(topic.topic_id, [])
            )
        return fallback_matches

    async def _load_deep_articles(self) -> list[Content]:
        """Load all articles from deep sources (no time limit).

        Ouvre une session courte dédiée : la requête dure <1s et les
        objets Content restent utilisables hors session (expire_on_commit=False,
        selectinload sur `source`). Cf. bug-infinite-load-requests.md (P1).
        """
        stmt = (
            select(Content)
            .join(Content.source)
            .options(selectinload(Content.source))
            .where(
                Source.source_tier == "deep",
                Content.is_paid.is_(False),
            )
            .order_by(Content.published_at.desc())
            .limit(3000)  # Safety cap
        )
        async with self._short_session() as session:
            result = await session.execute(stmt)
            return list(result.scalars().all())

    async def _expand_query(self, topic: SelectedTopic) -> set[str]:
        """Generate semantically adjacent keywords via small LLM."""
        prompt_cfg = self._config.query_expansion_prompt
        raw = await self._llm.chat_json(
            system=prompt_cfg.system,
            user_message=f"Sujet: {topic.label}\nAngle: {topic.deep_angle}",
            model=prompt_cfg.model,
            temperature=prompt_cfg.temperature,
            max_tokens=prompt_cfg.max_tokens,
        )
        if raw and isinstance(raw, dict):
            keywords = raw.get("keywords", [])
            if isinstance(keywords, list):
                return self._detector.normalize_title(
                    " ".join(str(k) for k in keywords)
                )
        return set()

    def _prefilter(
        self,
        topic: SelectedTopic,
        articles: list[Content],
        limit: int,
        threshold: float,
        extra_tokens: set[str] | None = None,
        cluster_entities: set[str] | None = None,
    ) -> list[tuple[Content, float]]:
        """Pass 1: Jaccard similarity pre-filter with entity overlap bonus."""
        # Tokenize topic label + deep_angle
        topic_tokens = self._detector.normalize_title(
            f"{topic.label} {topic.deep_angle}"
        )
        if extra_tokens:
            topic_tokens |= extra_tokens
        if not topic_tokens:
            return []

        scored: list[tuple[Content, float]] = []
        for article in articles:
            # Tokenize article title + topics + description excerpt
            article_text = article.title
            if article.topics:
                article_text += " " + " ".join(article.topics)
            if article.description:
                article_text += " " + article.description[:200]
            article_tokens = self._detector.normalize_title(article_text)

            similarity = self._detector.jaccard_similarity(topic_tokens, article_tokens)

            # Entity overlap bonus: shared named entities boost similarity
            if cluster_entities and article.entities:
                article_entity_names = {
                    e.split(":")[0].lower().strip()
                    for e in article.entities
                    if e and ":" in e
                }
                entity_overlap = len(cluster_entities & article_entity_names)
                if entity_overlap > 0:
                    similarity += min(0.05 * entity_overlap, 0.15)

            if similarity >= threshold:
                scored.append((article, similarity))

        # Sort by similarity desc, take top N
        scored.sort(key=lambda x: x[1], reverse=True)
        return scored[:limit]

    async def _llm_evaluate(
        self,
        topic: SelectedTopic,
        candidates: list[tuple[Content, float]],
    ) -> MatchedDeepArticle | None:
        """Pass 2: LLM picks best deep article from candidates."""
        if not candidates:
            return None

        # Format candidates for LLM
        candidates_text = "\n".join(
            f"[{i}] {c.title} — {c.source.name if c.source else 'Unknown'}"
            f" ({c.published_at.strftime('%Y-%m-%d')})"
            f"\n    {(c.description or '')[:200]}"
            for i, (c, _score) in enumerate(candidates)
        )

        prompt_cfg = self._config.deep_matching_prompt
        system = prompt_cfg.system.format(
            topic_label=topic.label,
            deep_angle=topic.deep_angle,
        )

        raw = await self._llm.chat_json(
            system=system,
            user_message=candidates_text,
            model=prompt_cfg.model,
            temperature=prompt_cfg.temperature,
            max_tokens=prompt_cfg.max_tokens,
        )

        if not raw or not isinstance(raw, dict):
            return self._fallback_pick(candidates)

        selected_index = raw.get("selected_index")
        reason = raw.get("reason", "")

        if selected_index is None:
            logger.info(
                "deep_matcher.llm_no_match",
                topic_id=topic.topic_id,
                reason=reason,
            )
            return None

        if (
            not isinstance(selected_index, int)
            or selected_index < 0
            or selected_index >= len(candidates)
        ):
            logger.warning(
                "deep_matcher.llm_invalid_index",
                index=selected_index,
                candidates_count=len(candidates),
            )
            return self._fallback_pick(candidates)

        content, _score = candidates[selected_index]
        source_name = content.source.name if content.source else "Source inconnue"

        return MatchedDeepArticle(
            content_id=content.id,
            title=content.title,
            source_name=source_name,
            source_id=content.source_id,
            published_at=content.published_at,
            match_reason=reason or f"Analyse de fond sur {topic.label}",
            description=content.description,
        )

    @staticmethod
    def _fallback_pick(
        candidates: list[tuple[Content, float]],
        min_score: float = 0.15,
    ) -> MatchedDeepArticle | None:
        """Fallback: pick top Jaccard candidate if above minimum threshold.

        Raised from 0.08 to 0.15 together with the removal of Pass 3
        broader fallback: the deterministic pick only runs when the LLM
        errored (exception), so the bar for accepting a weak match must
        be high — worse no article than a hors-sujet one.
        """
        if not candidates:
            return None

        content, score = candidates[0]

        # Reject weak matches — better no deep article than a bad one
        if score < min_score:
            logger.info(
                "deep_matcher.fallback_rejected",
                content_id=content.id,
                score=score,
                min_score=min_score,
            )
            return None

        source_name = content.source.name if content.source else "Source inconnue"

        return MatchedDeepArticle(
            content_id=content.id,
            title=content.title,
            source_name=source_name,
            source_id=content.source_id,
            published_at=content.published_at,
            match_reason="Selection automatique (meilleure correspondance)",
            description=content.description,
        )
