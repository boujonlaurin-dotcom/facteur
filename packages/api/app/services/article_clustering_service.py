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
) -> tuple[str | None, str | None, list[Content]]:
    """Find the biggest cluster of articles sharing entities within a time window.

    Args:
        articles: Pool of candidate articles (from pre_regroup_map.values())
        window_hours: Only consider articles published within this window
        max_items: Maximum articles to return
        min_items: Minimum articles for a valid cluster

    Returns:
        (entity_key, entity_display_name, clustered_articles)
        Returns (None, None, []) if no cluster found with >= min_items articles.
    """
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

    # Build entity -> articles index
    entity_to_articles: dict[str, list[Content]] = {}
    entity_display: dict[str, str] = {}  # key -> original casing

    for article in recent:
        entities = parse_entities(article)
        for ent in entities:
            entity_to_articles.setdefault(ent["key"], []).append(article)
            if ent["key"] not in entity_display:
                entity_display[ent["key"]] = ent["name"]

    if not entity_to_articles:
        return None, None, []

    # Find entity with most articles
    best_key = max(entity_to_articles, key=lambda k: len(entity_to_articles[k]))
    best_articles = entity_to_articles[best_key]

    if len(best_articles) < min_items:
        return None, None, []

    # Deduplicate (article can appear via multiple entities)
    seen_ids: set[UUID] = set()
    unique: list[Content] = []
    for a in best_articles:
        if a.id not in seen_ids:
            seen_ids.add(a.id)
            unique.append(a)

    # Sort by published_at DESC, take max_items
    unique.sort(key=lambda a: a.published_at, reverse=True)
    result = unique[:max_items]

    logger.info(
        "hot_cluster_found",
        entity=best_key,
        display_name=entity_display.get(best_key),
        cluster_size=len(unique),
        returned=len(result),
    )

    return best_key, entity_display.get(best_key, best_key.title()), result


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
    ).scalars().all()

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
