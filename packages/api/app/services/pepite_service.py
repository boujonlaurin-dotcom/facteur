"""Service "Pépites" — recommandations curées de sources dans le feed.

Critères d'affichage (uniformes pour tous les utilisateurs) :
- Rate-limit : max 1×/24h
- Cool-down : si dismissé récemment, attendre 7j
"""

from datetime import UTC, datetime, timedelta
from uuid import UUID

import structlog
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.source import Source, UserSource
from app.models.user import UserInterest
from app.models.user_personalization import UserPersonalization
from app.schemas.source import SourceResponse

logger = structlog.get_logger()

DISMISS_COOL_DOWN_DAYS = 7
RATE_LIMIT_HOURS = 24


def _now() -> datetime:
    return datetime.now(UTC)


def _as_utc(dt: datetime) -> datetime:
    return dt if dt.tzinfo is not None else dt.replace(tzinfo=UTC)


class PepiteService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def _load_personalization(
        self, user_uuid: UUID
    ) -> UserPersonalization | None:
        return await self.db.scalar(
            select(UserPersonalization).where(UserPersonalization.user_id == user_uuid)
        )

    @staticmethod
    def _rate_limited(personalization: UserPersonalization | None) -> bool:
        if (
            personalization is None
            or personalization.pepite_carousel_last_shown_at is None
        ):
            return False
        last_shown = _as_utc(personalization.pepite_carousel_last_shown_at)
        return last_shown > _now() - timedelta(hours=RATE_LIMIT_HOURS)

    @staticmethod
    def _in_cool_down(personalization: UserPersonalization | None) -> bool:
        if (
            personalization is None
            or personalization.pepite_carousel_dismissed_at is None
        ):
            return False
        dismissed_at = _as_utc(personalization.pepite_carousel_dismissed_at)
        return dismissed_at > _now() - timedelta(days=DISMISS_COOL_DOWN_DAYS)

    def _is_eligible(self, personalization: UserPersonalization | None) -> bool:
        if self._in_cool_down(personalization):
            return False
        return not self._rate_limited(personalization)

    async def should_show_pepite_carousel(self, user_id: str) -> bool:
        user_uuid = UUID(user_id)
        personalization = await self._load_personalization(user_uuid)
        return self._is_eligible(personalization)

    async def _user_interest_slugs(self, user_uuid: UUID) -> set[str]:
        result = await self.db.execute(
            select(UserInterest.interest_slug).where(UserInterest.user_id == user_uuid)
        )
        return {row[0] for row in result.all()}

    async def _user_followed_source_ids(self, user_uuid: UUID) -> set[UUID]:
        result = await self.db.execute(
            select(UserSource.source_id).where(UserSource.user_id == user_uuid)
        )
        return set(result.scalars().all())

    async def _ensure_personalization(
        self, user_uuid: UUID, personalization: UserPersonalization | None
    ) -> UserPersonalization:
        if personalization is not None:
            return personalization
        created = UserPersonalization(user_id=user_uuid)
        self.db.add(created)
        return created

    async def get_pepites_for_user(
        self, user_id: str, limit: int = 4
    ) -> list[SourceResponse]:
        """Retourne jusqu'à `limit` sources pépites pour l'utilisateur.

        Liste vide si aucun trigger actif, rate-limit, ou cool-down.
        """
        user_uuid = UUID(user_id)
        personalization = await self._load_personalization(user_uuid)

        if not self._is_eligible(personalization):
            return []

        followed_ids = await self._user_followed_source_ids(user_uuid)
        interest_slugs = await self._user_interest_slugs(user_uuid)

        muted_ids: set[UUID] = (
            set(personalization.muted_sources)
            if personalization and personalization.muted_sources
            else set()
        )
        excluded_ids = followed_ids | muted_ids

        count_col = func.count(UserSource.user_id).label("follower_count")
        query = (
            select(Source, count_col)
            .outerjoin(UserSource, UserSource.source_id == Source.id)
            .where(Source.is_pepite_recommendation)
            .where(Source.is_active)
            .group_by(Source.id)
        )
        if excluded_ids:
            query = query.where(Source.id.notin_(excluded_ids))

        result = await self.db.execute(query)
        rows = result.all()

        def _match_score(source: Source) -> int:
            if not source.pepite_for_themes or not interest_slugs:
                return 0
            return len(set(source.pepite_for_themes) & interest_slugs)

        rows.sort(
            key=lambda row: (_match_score(row[0]), row[1] or 0),
            reverse=True,
        )

        selected = rows[:limit]
        if not selected:
            return []

        personalization = await self._ensure_personalization(user_uuid, personalization)
        personalization.pepite_carousel_last_shown_at = _now()
        await self.db.flush()

        return [
            SourceResponse(
                id=s.id,
                name=s.name,
                url=s.url,
                type=s.type,
                theme=s.theme,
                description=s.description,
                logo_url=s.logo_url,
                is_curated=s.is_curated,
                is_custom=not s.is_curated,
                is_trusted=False,
                is_muted=False,
                content_count=0,
                follower_count=follower_count or 0,
                bias_stance=getattr(s.bias_stance, "value", "unknown"),
                reliability_score=getattr(s.reliability_score, "value", "unknown"),
                bias_origin=getattr(s.bias_origin, "value", "unknown"),
                secondary_themes=s.secondary_themes,
                granular_topics=s.granular_topics,
                source_tier=s.source_tier or "mainstream",
                score_independence=s.score_independence,
                score_rigor=s.score_rigor,
                score_ux=s.score_ux,
                editorial_note=getattr(s, "editorial_note", None),
            )
            for s, follower_count in selected
        ]

    async def dismiss_pepite_carousel(self, user_id: str) -> None:
        user_uuid = UUID(user_id)
        personalization = await self._load_personalization(user_uuid)
        personalization = await self._ensure_personalization(user_uuid, personalization)
        personalization.pepite_carousel_dismissed_at = _now()
        await self.db.flush()
        logger.info("pepite_carousel_dismissed", user_id=user_id)
