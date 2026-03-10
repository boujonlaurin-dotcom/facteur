"""ÉTAPE 3B — Deep source article matching.

Two-pass strategy:
  Pass 1: Jaccard pre-filter (no LLM) → top N candidates
  Pass 2: LLM evaluates candidates and picks best match

No time limit on deep articles (can be months old).
"""

from __future__ import annotations

import asyncio
import json
from uuid import UUID

import structlog
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.content import Content
from app.models.source import Source
from app.services.briefing.importance_detector import ImportanceDetector
from app.services.editorial.config import EditorialConfig
from app.services.editorial.llm_client import AnthropicClient
from app.services.editorial.schemas import MatchedDeepArticle, SelectedTopic

logger = structlog.get_logger()


class DeepMatcher:
    """Matches editorial topics to deep source articles."""

    def __init__(
        self,
        session: AsyncSession,
        llm: AnthropicClient,
        config: EditorialConfig,
    ) -> None:
        self._session = session
        self._llm = llm
        self._config = config
        self._detector = ImportanceDetector()

    async def match_for_topics(
        self,
        selected_topics: list[SelectedTopic],
    ) -> dict[str, MatchedDeepArticle | None]:
        """Match deep articles for all topics.

        Returns:
            Dict mapping topic_id to MatchedDeepArticle or None.
        """
        # Load all deep source articles once
        deep_articles = await self._load_deep_articles()
        if not deep_articles:
            logger.warning("deep_matcher.no_deep_articles")
            return {t.topic_id: None for t in selected_topics}

        logger.info("deep_matcher.pool_loaded", count=len(deep_articles))

        # Pass 1: Pre-filter per topic
        prefilter_limit = self._config.pipeline.deep_candidates_prefilter
        threshold = self._config.pipeline.deep_jaccard_threshold
        candidates_per_topic: dict[str, list[tuple[Content, float]]] = {}

        for topic in selected_topics:
            candidates = self._prefilter(
                topic=topic,
                articles=deep_articles,
                limit=prefilter_limit,
                threshold=threshold,
            )
            candidates_per_topic[topic.topic_id] = candidates
            logger.info(
                "deep_matcher.prefilter",
                topic_id=topic.topic_id,
                candidates=len(candidates),
            )

        # Pass 2: LLM evaluation (parallel)
        if self._llm.is_ready:
            tasks = [
                self._llm_evaluate(topic, candidates_per_topic.get(topic.topic_id, []))
                for topic in selected_topics
            ]
            results = await asyncio.gather(*tasks, return_exceptions=True)

            matches: dict[str, MatchedDeepArticle | None] = {}
            for topic, result in zip(selected_topics, results):
                if isinstance(result, Exception):
                    logger.error(
                        "deep_matcher.llm_error",
                        topic_id=topic.topic_id,
                        error=str(result),
                    )
                    # Fallback: top Jaccard candidate
                    matches[topic.topic_id] = self._fallback_pick(
                        candidates_per_topic.get(topic.topic_id, [])
                    )
                else:
                    matches[topic.topic_id] = result
            return matches

        # No LLM: use Jaccard fallback for all
        logger.info("deep_matcher.no_llm_fallback_all")
        return {
            topic.topic_id: self._fallback_pick(
                candidates_per_topic.get(topic.topic_id, [])
            )
            for topic in selected_topics
        }

    async def _load_deep_articles(self) -> list[Content]:
        """Load all articles from deep sources (no time limit)."""
        stmt = (
            select(Content)
            .join(Content.source)
            .options(selectinload(Content.source))
            .where(
                Source.source_tier == "deep",
                Content.is_paid.is_(False),
            )
            .order_by(Content.published_at.desc())
            .limit(500)  # Safety cap
        )
        result = await self._session.execute(stmt)
        return list(result.scalars().all())

    def _prefilter(
        self,
        topic: SelectedTopic,
        articles: list[Content],
        limit: int,
        threshold: float,
    ) -> list[tuple[Content, float]]:
        """Pass 1: Jaccard similarity pre-filter."""
        # Tokenize topic label + deep_angle
        topic_tokens = self._detector.normalize_title(
            f"{topic.label} {topic.deep_angle}"
        )
        if not topic_tokens:
            return []

        scored: list[tuple[Content, float]] = []
        for article in articles:
            # Tokenize article title + topics
            article_text = article.title
            if article.topics:
                article_text += " " + " ".join(article.topics)
            article_tokens = self._detector.normalize_title(article_text)

            similarity = self._detector.jaccard_similarity(topic_tokens, article_tokens)
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

        if not isinstance(selected_index, int) or selected_index < 0 or selected_index >= len(candidates):
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
        )

    @staticmethod
    def _fallback_pick(
        candidates: list[tuple[Content, float]],
    ) -> MatchedDeepArticle | None:
        """Fallback: pick top Jaccard candidate."""
        if not candidates:
            return None

        content, _score = candidates[0]
        source_name = content.source.name if content.source else "Source inconnue"

        return MatchedDeepArticle(
            content_id=content.id,
            title=content.title,
            source_name=source_name,
            source_id=content.source_id,
            published_at=content.published_at,
            match_reason="Selection automatique (meilleure correspondance)",
        )
