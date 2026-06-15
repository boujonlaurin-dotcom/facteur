"""Article clustering service for carousel building.

Provides entity-based clustering for hot news detection (T4)
and read-article-based perspective finding (T5).
"""

import json
from datetime import UTC, datetime, timedelta
from uuid import UUID

import structlog
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.content import Content, UserContentStatus
from app.models.enums import ContentStatus

logger = structlog.get_logger(__name__)


def parse_entities(article: Content) -> list[dict]:
    """Parse entity JSON strings from a Content's entities array.

    Returns list of dicts with keys: name, type, key (lowercase name).
    Deduplicates by lowercase name.
    """
    if not article.entities:
        return []
    seen: set[str] = set()
    result: list[dict] = []
    for raw in article.entities:
        try:
            obj = json.loads(raw)
            name = obj.get("name", "").strip()
            etype = obj.get("type", "")
            key = name.lower()
            if name and key not in seen:
                seen.add(key)
                result.append({"name": name, "type": etype, "key": key})
        except (ValueError, TypeError):
            continue
    return result


def find_hot_cluster(
    articles: list[Content],
    window_hours: int = 36,
    max_items: int = 5,
    min_items: int = 3,
    seed: int | None = None,
) -> tuple[str | None, str | None, list[Content]]:
    """Find a hot cluster of articles covering the same story within a window.

    Reuses the topic clustering that powers the daily digest
    (`ImportanceDetector.build_topic_clusters`, similarité Jaccard des titres,
    couverte par le harness de calibration) instead of the old grouping by a
    single shared NER entity, which clustered unrelated articles on passing
    mentions (e.g. "Trump" cited once in each).

    Selects probabilistically among the top-3 eligible clusters (weighted by
    size) instead of always picking the largest. This adds daily variety.

    Args:
        articles: Pool of candidate articles (from pre_regroup_map.values())
        window_hours: Only consider articles published within this window
        max_items: Maximum articles to return
        min_items: Minimum articles for a valid cluster
        seed: Optional RNG seed for deterministic selection (e.g. hash of user_id+date)

    Returns:
        (cluster_key, display_name, clustered_articles). cluster_key is the
        cluster's label (deterministic for a given input pool, unlike the
        random TopicCluster.cluster_id). display_name is the cluster's
        dominant entity, or None when no entity is shared by at least 2 of
        its articles. Returns (None, None, []) if no cluster has
        >= min_items articles from >= 2 sources.
    """
    import random as _random
    from collections import Counter

    from app.services.briefing.importance_detector import ImportanceDetector

    cutoff = datetime.now(UTC) - timedelta(hours=window_hours)

    # Filter to recent articles only
    recent: list[Content] = []
    for a in articles:
        pub = a.published_at
        if pub.tzinfo is None:
            pub = pub.replace(tzinfo=UTC)
        if pub >= cutoff:
            recent.append(a)

    if len(recent) < min_items:
        return None, None, []

    clusters = ImportanceDetector().build_topic_clusters(recent)

    # Eligible: enough articles AND multi-source (one source pushing many
    # takes on the same story is not "hot news").
    eligible = [
        c for c in clusters if len(c.contents) >= min_items and c.is_multi_source
    ]
    if not eligible:
        return None, None, []

    # build_topic_clusters returns clusters sorted by size DESC — keep top 3
    top_candidates = eligible[:3]

    # Weighted random selection among top candidates
    rng = _random.Random(seed)
    weights = [len(c.contents) for c in top_candidates]
    (best,) = rng.choices(top_candidates, weights=weights, k=1)

    # Display name: dominant entity across the cluster's articles. Entities
    # are used for labelling only, never for grouping; require >= 2 articles
    # sharing it so a passing mention can't title the carousel.
    entity_counts: Counter = Counter()
    entity_display: dict[str, str] = {}
    for a in best.contents:
        for ent in parse_entities(a):
            entity_counts[ent["key"]] += 1
            entity_display.setdefault(ent["key"], ent["name"])
    display_name: str | None = None
    if entity_counts:
        top_key, top_count = entity_counts.most_common(1)[0]
        if top_count >= 2:
            display_name = entity_display[top_key]

    # Sort by published_at DESC, take max_items
    unique = sorted(best.contents, key=lambda a: a.published_at, reverse=True)
    result = unique[:max_items]

    logger.info(
        "hot_cluster_found",
        cluster_key=best.label,
        display_name=display_name,
        cluster_size=len(best.contents),
        returned=len(result),
        candidates_considered=len(top_candidates),
    )

    return best.label, display_name, result


async def find_perspectives_for_read_article(
    session: AsyncSession,
    user_id: UUID,
    articles_pool: dict[UUID, Content],
    max_items: int = 5,
    lookback_days: int = 7,
) -> tuple[Content | None, list[Content]]:
    """Find internal perspectives based on a recently read article.

    Finds the consumed article with the most entity-matching articles
    in the pool (from different sources), then returns those as perspectives.

    Args:
        session: DB session
        user_id: Current user
        articles_pool: All available articles (pre_regroup_map)
        max_items: Max total items (reference + perspectives)
        lookback_days: How far back to look for consumed articles

    Returns:
        (reference_article, perspective_articles)
        Returns (None, []) if no suitable reference found.
    """
    cutoff = datetime.now(UTC) - timedelta(days=lookback_days)

    # Get recently consumed article IDs
    consumed_rows = (
        (
            await session.execute(
                select(UserContentStatus.content_id)
                .where(
                    UserContentStatus.user_id == user_id,
                    UserContentStatus.status == ContentStatus.CONSUMED,
                    UserContentStatus.updated_at >= cutoff,
                )
                .order_by(UserContentStatus.updated_at.desc())
                .limit(50)  # Cap for performance
            )
        )
        .scalars()
        .all()
    )

    if not consumed_rows:
        logger.info("perspectives_no_consumed", user_id=str(user_id))
        return None, []

    # Load consumed articles with source eager-loaded
    consumed_articles = list(
        (
            await session.scalars(
                select(Content)
                .options(selectinload(Content.source))
                .where(Content.id.in_(consumed_rows))
            )
        ).all()
    )

    if not consumed_articles:
        return None, []

    # Pre-parse entities for all pool articles
    pool_entities: dict[UUID, set[str]] = {}
    for aid, article in articles_pool.items():
        ents = parse_entities(article)
        pool_entities[aid] = {e["key"] for e in ents}

    # For each consumed article, count entity matches in pool
    best_ref: Content | None = None
    best_matches: list[tuple[int, Content]] = []
    best_count = 0

    for consumed in consumed_articles:
        consumed_ents = parse_entities(consumed)
        if not consumed_ents:
            continue

        consumed_keys = {e["key"] for e in consumed_ents}
        matches: list[tuple[int, Content]] = []

        for aid, article in articles_pool.items():
            if aid == consumed.id:
                continue
            if article.source_id == consumed.source_id:
                continue  # Different source = real perspective

            article_keys = pool_entities.get(aid, set())
            shared = len(consumed_keys & article_keys)
            if shared > 0:
                matches.append((shared, article))

        if len(matches) > best_count:
            best_count = len(matches)
            best_ref = consumed
            # Sort by shared entity count DESC, then by published_at DESC
            matches.sort(key=lambda x: (-x[0], -x[1].published_at.timestamp()))
            best_matches = matches

    if best_ref is None or not best_matches:
        logger.info(
            "perspectives_no_match",
            user_id=str(user_id),
            consumed_count=len(consumed_articles),
        )
        return None, []

    perspective_articles = [m[1] for m in best_matches[: max_items - 1]]

    logger.info(
        "perspectives_found",
        user_id=str(user_id),
        reference_id=str(best_ref.id),
        reference_title=best_ref.title[:60],
        perspective_count=len(perspective_articles),
        best_shared_entities=best_matches[0][0] if best_matches else 0,
    )

    return best_ref, perspective_articles
