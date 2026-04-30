"""Service de recommandations communautaires (carrousels 🌻).

Scoring avec decay temporel :
  score(article) = SUM(1 / (1 + heures_depuis_sunflower / 48))

Deux surfaces :
- Digest : articles les plus recemment 🌻 (tri par fraicheur)
- Feed : meilleurs articles sur 7 jours (tri par score decay)
"""

import datetime

import structlog
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.content import Content, UserContentStatus

logger = structlog.get_logger()

# Window for community recommendations (7 days)
COMMUNITY_WINDOW_DAYS = 7
# Decay half-life in hours (score = 0.5 after 48h)
DECAY_HALF_LIFE_HOURS = 48
# Min/max items per carousel
MIN_CAROUSEL_ITEMS = 3
MAX_CAROUSEL_ITEMS = 8


class CommunityRecommendationService:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def get_top_recommendations(
        self,
        limit: int = MAX_CAROUSEL_ITEMS,
        exclude_ids: set | None = None,
    ) -> list[dict]:
        """Feed carousel: best articles over 7 days, scored by decay.

        Returns articles sorted by weighted score (descending).
        Each dict contains: content (Content), sunflower_count (int), score (float).
        """
        now = datetime.datetime.now(datetime.UTC)
        window_start = now - datetime.timedelta(days=COMMUNITY_WINDOW_DAYS)

        # Decay formula: 1 / (1 + hours_since / 48)
        # In SQL: hours_since = EXTRACT(EPOCH FROM (now - liked_at)) / 3600
        hours_since = func.extract("epoch", now - UserContentStatus.liked_at) / 3600.0
        decay_weight = 1.0 / (1.0 + hours_since / DECAY_HALF_LIFE_HOURS)

        exclusion = Content.id.notin_(exclude_ids) if exclude_ids else True

        rows = (
            await self.session.execute(
                select(
                    Content.id,
                    func.sum(decay_weight).label("score"),
                    func.count(UserContentStatus.id).label("sunflower_count"),
                )
                .join(
                    UserContentStatus,
                    UserContentStatus.content_id == Content.id,
                )
                .where(
                    UserContentStatus.is_liked.is_(True),
                    UserContentStatus.liked_at >= window_start,
                    exclusion,
                )
                .group_by(Content.id)
                .having(func.count(UserContentStatus.id) >= 1)
                .order_by(func.sum(decay_weight).desc())
                .limit(limit)
            )
        ).all()

        if not rows:
            return []

        # Fetch full Content objects with source
        content_ids = [r.id for r in rows]
        score_map = {r.id: float(r.score) for r in rows}
        count_map = {r.id: int(r.sunflower_count) for r in rows}

        contents = list(
            (
                await self.session.scalars(
                    select(Content)
                    .options(selectinload(Content.source))
                    .where(Content.id.in_(content_ids))
                )
            ).all()
        )

        # Maintain score order
        id_order = {cid: i for i, cid in enumerate(content_ids)}
        contents.sort(key=lambda c: id_order.get(c.id, 99))

        return [
            {
                "content": c,
                "sunflower_count": count_map.get(c.id, 0),
                "score": score_map.get(c.id, 0.0),
            }
            for c in contents
        ]

    async def get_recent_recommendations(
        self,
        limit: int = MAX_CAROUSEL_ITEMS,
        exclude_ids: set | None = None,
    ) -> list[dict]:
        """Digest carousel: most recently sunflowered articles.

        Returns articles sorted by most recent sunflower timestamp (descending).
        Each dict contains: content (Content), sunflower_count (int).
        """
        now = datetime.datetime.now(datetime.UTC)
        window_start = now - datetime.timedelta(days=COMMUNITY_WINDOW_DAYS)

        exclusion = Content.id.notin_(exclude_ids) if exclude_ids else True

        rows = (
            await self.session.execute(
                select(
                    Content.id,
                    func.count(UserContentStatus.id).label("sunflower_count"),
                    func.max(UserContentStatus.liked_at).label("latest_sunflower"),
                )
                .join(
                    UserContentStatus,
                    UserContentStatus.content_id == Content.id,
                )
                .where(
                    UserContentStatus.is_liked.is_(True),
                    UserContentStatus.liked_at >= window_start,
                    exclusion,
                )
                .group_by(Content.id)
                .having(func.count(UserContentStatus.id) >= 1)
                .order_by(func.max(UserContentStatus.liked_at).desc())
                .limit(limit)
            )
        ).all()

        if not rows:
            return []

        content_ids = [r.id for r in rows]
        count_map = {r.id: int(r.sunflower_count) for r in rows}

        contents = list(
            (
                await self.session.scalars(
                    select(Content)
                    .options(selectinload(Content.source))
                    .where(Content.id.in_(content_ids))
                )
            ).all()
        )

        id_order = {cid: i for i, cid in enumerate(content_ids)}
        contents.sort(key=lambda c: id_order.get(c.id, 99))

        return [
            {
                "content": c,
                "sunflower_count": count_map.get(c.id, 0),
            }
            for c in contents
        ]

    async def get_community_carousels(
        self,
    ) -> tuple[list[dict], list[dict]]:
        """Build both community carousels.

        Feed and Digest live on separate screens, so overlap between the two
        is acceptable. The Digest screen also re-dedupes against the main
        digest items on the mobile side. Excluding feed_ids here used to
        empty the digest carousel whenever the community-wide like pool was
        small (≤ MAX_CAROUSEL_ITEMS), which is the steady state today.

        Returns: (feed_items, digest_items)
        """
        feed_items = await self.get_top_recommendations(limit=MAX_CAROUSEL_ITEMS)
        digest_items = await self.get_recent_recommendations(limit=MAX_CAROUSEL_ITEMS)

        logger.info(
            "community_carousels_built",
            feed_count=len(feed_items),
            digest_count=len(digest_items),
        )

        return feed_items, digest_items
