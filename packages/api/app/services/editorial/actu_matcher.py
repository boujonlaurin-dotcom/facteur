"""ÉTAPE 3A — Actu article matching (per-user).

For each editorial subject, finds the best recent article
from the user's followed sources. No LLM calls.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import UUID

import structlog

from app.services.briefing.importance_detector import TopicCluster
from app.services.editorial.schemas import EditorialSubject, MatchedActuArticle

logger = structlog.get_logger()


class ActuMatcher:
    """Matches editorial topics to news articles from user's sources."""

    def __init__(self, actu_max_age_hours: int = 24) -> None:
        self._max_age_hours = actu_max_age_hours

    def match_for_user(
        self,
        subjects: list[EditorialSubject],
        clusters: list[TopicCluster],
        user_source_ids: set[UUID],
        excluded_content_ids: set[UUID],
    ) -> list[EditorialSubject]:
        """Match actu articles for each subject (in-memory, no DB calls).

        Articles come from TopicCluster.contents (already loaded in memory
        during global context computation).

        Args:
            subjects: Editorial subjects (with deep matches, no actu yet).
            clusters: Raw TopicCluster list from global context.
            user_source_ids: User's followed source UUIDs.
            excluded_content_ids: Already-seen/dismissed content UUIDs.

        Returns:
            Updated subjects with actu_article populated.
        """
        # Build cluster lookup by ID
        cluster_map = {c.cluster_id: c for c in clusters}
        cutoff = datetime.now(UTC) - timedelta(hours=self._max_age_hours)

        # Track used sources across subjects for diversity
        used_source_ids: set[UUID] = set()
        result: list[EditorialSubject] = []

        for subject in subjects:
            cluster = cluster_map.get(subject.topic_id)
            if not cluster:
                logger.warning(
                    "actu_matcher.cluster_not_found",
                    topic_id=subject.topic_id,
                )
                result.append(subject)
                continue

            matched = self._find_best_article(
                cluster=cluster,
                user_source_ids=user_source_ids,
                excluded_ids=excluded_content_ids,
                used_source_ids=used_source_ids,
                cutoff=cutoff,
            )

            if matched:
                used_source_ids.add(matched.source_id)
                updated = subject.model_copy(update={"actu_article": matched})
            else:
                updated = subject

            result.append(updated)

        matched_count = sum(1 for s in result if s.actu_article is not None)
        logger.info(
            "actu_matcher.done",
            matched=matched_count,
            total=len(subjects),
        )
        return result

    def match_global(
        self,
        subjects: list[EditorialSubject],
        clusters: list[TopicCluster],
        excluded_source_ids: set[UUID] | None = None,
    ) -> list[EditorialSubject]:
        """Match best actu article per subject from ALL sources (no user filter).

        MVP V2: digest is identical for all users — pick the best article
        from the entire cluster (most recent, non-paywall).

        Args:
            subjects: Editorial subjects (with deep matches, no actu yet).
            clusters: Raw TopicCluster list from global context.
            excluded_source_ids: Source IDs to exclude (e.g. deep article sources).

        Returns:
            Updated subjects with actu_article populated.
        """
        cluster_map = {c.cluster_id: c for c in clusters}
        cutoff = datetime.now(UTC) - timedelta(hours=self._max_age_hours)
        # Per-subject exclusion only: each subject excludes its own deep source,
        # but deep sources from OTHER subjects are allowed as actu candidates.
        # Cross-subject actu diversity is maintained by accumulating used sources below.
        used_source_ids: set[UUID] = set()
        result: list[EditorialSubject] = []

        for subject in subjects:
            cluster = cluster_map.get(subject.topic_id)
            if not cluster:
                logger.warning(
                    "actu_matcher.cluster_not_found",
                    topic_id=subject.topic_id,
                )
                result.append(subject)
                continue

            # Per-subject: exclude this subject's deep article source
            per_subject_excluded = set(used_source_ids)
            if subject.deep_article is not None:
                per_subject_excluded.add(subject.deep_article.source_id)

            best = self._find_best_article_global(
                cluster=cluster,
                used_source_ids=per_subject_excluded,
                cutoff=cutoff,
            )
            if best:
                used_source_ids.add(best.source_id)
                result.append(subject.model_copy(update={"actu_article": best}))
            else:
                logger.warning(
                    "actu_matcher.no_global_match",
                    topic_id=subject.topic_id,
                    cluster_content_count=len(cluster.contents),
                )
                result.append(subject)

        # Pass 2+3: relax filters for unmatched subjects
        cutoff_relaxed = datetime.now(UTC) - timedelta(hours=self._max_age_hours * 2)
        relaxed_used: set[UUID] = set()
        for i, subject in enumerate(result):
            if subject.actu_article is not None:
                continue
            cluster = cluster_map.get(subject.topic_id)
            if not cluster:
                continue
            # Try without pass-1 diversity, but keep diversity among relaxed matches
            best = self._find_best_article_global(
                cluster=cluster,
                used_source_ids=relaxed_used,
                cutoff=cutoff,
            )
            if not best:
                # Try with relaxed recency (48h)
                best = self._find_best_article_global(
                    cluster=cluster,
                    used_source_ids=relaxed_used,
                    cutoff=cutoff_relaxed,
                )
            if best:
                relaxed_used.add(best.source_id)
                result[i] = subject.model_copy(update={"actu_article": best})
                logger.info("actu_matcher.relaxed_match", topic_id=subject.topic_id)

        matched_count = sum(1 for s in result if s.actu_article is not None)
        logger.info(
            "actu_matcher.global_done",
            matched=matched_count,
            total=len(subjects),
        )
        return result

    def _find_best_article_global(
        self,
        cluster: TopicCluster,
        used_source_ids: set[UUID],
        cutoff: datetime,
    ) -> MatchedActuArticle | None:
        """Best article from ANY source (not just user's).

        Constraints:
        - published_at >= cutoff (< 24h)
        - is_paid = false
        - Source not already used (diversity)
        """
        candidates = []
        for content in cluster.contents:
            if content.is_paid:
                continue
            if content.published_at.replace(tzinfo=UTC) < cutoff:
                continue
            if content.source_id in used_source_ids:
                continue
            candidates.append(content)

        candidates.sort(key=lambda c: c.published_at, reverse=True)
        if not candidates:
            return None

        content = candidates[0]
        return MatchedActuArticle(
            content_id=content.id,
            title=content.title,
            source_name=content.source.name if content.source else "Source inconnue",
            source_id=content.source_id,
            is_user_source=False,  # MVP: no user distinction
            published_at=content.published_at,
        )

    def _find_best_article(
        self,
        cluster: TopicCluster,
        user_source_ids: set[UUID],
        excluded_ids: set[UUID],
        used_source_ids: set[UUID],
        cutoff: datetime,
    ) -> MatchedActuArticle | None:
        """Find the best actu article from a cluster.

        Priority:
        1. User's followed sources (most recent first)
        2. Any mainstream source (fallback)

        Constraints:
        - published_at >= cutoff (< 24h)
        - is_paid = false
        - Not in excluded_ids
        - Source not already used (diversity)
        """
        candidates_user: list[tuple] = []  # (content, is_user_source)
        candidates_other: list[tuple] = []

        for content in cluster.contents:
            # Basic filters
            if content.id in excluded_ids:
                continue
            if content.is_paid:
                continue
            if content.published_at.replace(tzinfo=UTC) < cutoff:
                continue
            if content.source_id in used_source_ids:
                continue

            if content.source_id in user_source_ids:
                candidates_user.append((content, True))
            else:
                candidates_other.append((content, False))

        # Sort by recency (most recent first)
        candidates_user.sort(key=lambda x: x[0].published_at, reverse=True)
        candidates_other.sort(key=lambda x: x[0].published_at, reverse=True)

        # Pick best: user source preferred, then any
        best = (
            candidates_user[0]
            if candidates_user
            else candidates_other[0]
            if candidates_other
            else None
        )

        if not best:
            return None

        content, is_user_source = best
        source_name = content.source.name if content.source else "Source inconnue"

        return MatchedActuArticle(
            content_id=content.id,
            title=content.title,
            source_name=source_name,
            source_id=content.source_id,
            is_user_source=is_user_source,
            published_at=content.published_at,
        )
