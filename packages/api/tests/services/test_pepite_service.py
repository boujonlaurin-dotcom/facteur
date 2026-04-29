"""Tests for PepiteService (Story 13.2 — Feed Pepites Carousel).

Mock-based tests (no DB required) couvrant :
- Rate-limit uniforme (24h pour tous)
- Cool-down (dismiss → 7j)
- Selection logic (exclusion, theme priority, touch last_shown)
- Dismiss
"""

from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest

from app.models.enums import SourceType
from app.services.pepite_service import (
    DISMISS_COOL_DOWN_DAYS,
    RATE_LIMIT_HOURS,
    PepiteService,
)


def _now():
    return datetime.now(UTC)


def _mk_source(
    *,
    name="Src",
    theme="tech",
    is_curated=True,
    pepite_for_themes=None,
    source_id=None,
):
    return SimpleNamespace(
        id=source_id or uuid4(),
        name=name,
        url=f"https://{name.lower().replace(' ', '')}.example.com",
        type=SourceType.ARTICLE,
        theme=theme,
        description=None,
        logo_url=None,
        is_curated=is_curated,
        is_active=True,
        is_pepite_recommendation=True,
        pepite_for_themes=pepite_for_themes,
        bias_stance=SimpleNamespace(value="unknown"),
        reliability_score=SimpleNamespace(value="unknown"),
        bias_origin=SimpleNamespace(value="unknown"),
        secondary_themes=None,
        granular_topics=None,
        source_tier="mainstream",
        score_independence=None,
        score_rigor=None,
        score_ux=None,
    )


class TestRateLimitPredicate:
    def test_not_rate_limited_when_personalization_none(self):
        assert PepiteService._rate_limited(None) is False

    def test_not_rate_limited_when_last_shown_none(self):
        perso = SimpleNamespace(pepite_carousel_last_shown_at=None)
        assert PepiteService._rate_limited(perso) is False

    def test_rate_limited_recent(self):
        perso = SimpleNamespace(
            pepite_carousel_last_shown_at=_now() - timedelta(hours=1),
        )
        assert PepiteService._rate_limited(perso) is True

    def test_not_rate_limited_past_24h(self):
        perso = SimpleNamespace(
            pepite_carousel_last_shown_at=_now()
            - timedelta(hours=RATE_LIMIT_HOURS + 1),
        )
        assert PepiteService._rate_limited(perso) is False

    def test_handles_naive_datetime(self):
        naive = datetime.utcnow() - timedelta(hours=1)
        perso = SimpleNamespace(pepite_carousel_last_shown_at=naive)
        assert PepiteService._rate_limited(perso) is True


class TestCoolDownPredicate:
    def test_not_in_cool_down_when_personalization_none(self):
        assert PepiteService._in_cool_down(None) is False

    def test_not_in_cool_down_when_dismissed_none(self):
        perso = SimpleNamespace(pepite_carousel_dismissed_at=None)
        assert PepiteService._in_cool_down(perso) is False

    def test_in_cool_down_when_recently_dismissed(self):
        perso = SimpleNamespace(
            pepite_carousel_dismissed_at=_now() - timedelta(days=1),
        )
        assert PepiteService._in_cool_down(perso) is True

    def test_cool_down_expires(self):
        perso = SimpleNamespace(
            pepite_carousel_dismissed_at=_now()
            - timedelta(days=DISMISS_COOL_DOWN_DAYS + 1),
        )
        assert PepiteService._in_cool_down(perso) is False


class TestShouldShow:
    @pytest.mark.asyncio
    async def test_blocked_by_cool_down(self):
        session = AsyncMock()
        perso = SimpleNamespace(
            pepite_carousel_last_shown_at=None,
            pepite_carousel_dismissed_at=_now() - timedelta(days=1),
        )
        session.scalar = AsyncMock(return_value=perso)
        session.execute = AsyncMock()

        service = PepiteService(session)
        assert await service.should_show_pepite_carousel(str(uuid4())) is False

    @pytest.mark.asyncio
    async def test_blocked_by_rate_limit(self):
        session = AsyncMock()
        perso = SimpleNamespace(
            pepite_carousel_last_shown_at=_now() - timedelta(hours=1),
            pepite_carousel_dismissed_at=None,
        )
        session.scalar = AsyncMock(return_value=perso)

        service = PepiteService(session)
        assert await service.should_show_pepite_carousel(str(uuid4())) is False

    @pytest.mark.asyncio
    async def test_allows_when_no_personalization(self):
        session = AsyncMock()
        session.scalar = AsyncMock(return_value=None)

        service = PepiteService(session)
        assert await service.should_show_pepite_carousel(str(uuid4())) is True

    @pytest.mark.asyncio
    async def test_allows_when_past_24h(self):
        session = AsyncMock()
        perso = SimpleNamespace(
            pepite_carousel_last_shown_at=_now() - timedelta(hours=25),
            pepite_carousel_dismissed_at=None,
        )
        session.scalar = AsyncMock(return_value=perso)

        service = PepiteService(session)
        assert await service.should_show_pepite_carousel(str(uuid4())) is True


class TestSelection:
    @pytest.mark.asyncio
    async def test_returns_empty_when_rate_limited(self):
        session = AsyncMock()
        perso = SimpleNamespace(
            pepite_carousel_last_shown_at=_now() - timedelta(hours=1),
            pepite_carousel_dismissed_at=None,
        )
        session.scalar = AsyncMock(return_value=perso)

        service = PepiteService(session)
        results = await service.get_pepites_for_user(str(uuid4()))
        assert results == []

    @pytest.mark.asyncio
    async def test_excludes_followed_and_muted(self):
        session = AsyncMock()
        user_id = uuid4()

        followed_id = uuid4()
        muted_id = uuid4()
        visible = _mk_source(name="Visible", theme="tech")

        perso = SimpleNamespace(
            pepite_carousel_last_shown_at=None,
            pepite_carousel_dismissed_at=None,
            muted_sources=[muted_id],
        )
        session.scalar = AsyncMock(return_value=perso)

        # execute() call order:
        # 1. followed IDs
        # 2. interest slugs
        # 3. candidate query
        followed_result = MagicMock()
        followed_result.scalars.return_value.all.return_value = [followed_id]
        interests_result = MagicMock()
        interests_result.all.return_value = []
        sources_result = MagicMock()
        sources_result.all.return_value = [(visible, 3)]

        session.execute = AsyncMock(
            side_effect=[followed_result, interests_result, sources_result]
        )

        service = PepiteService(session)
        results = await service.get_pepites_for_user(str(user_id))
        assert len(results) == 1
        assert results[0].name == "Visible"
        assert results[0].follower_count == 3

    @pytest.mark.asyncio
    async def test_prioritizes_theme_match(self):
        session = AsyncMock()
        match = _mk_source(name="Match", theme="tech", pepite_for_themes=["tech"])
        no_match = _mk_source(
            name="NoMatch", theme="international", pepite_for_themes=["international"]
        )

        perso = SimpleNamespace(
            pepite_carousel_last_shown_at=None,
            pepite_carousel_dismissed_at=None,
            muted_sources=[],
        )
        session.scalar = AsyncMock(return_value=perso)

        followed_result = MagicMock()
        followed_result.scalars.return_value.all.return_value = []
        interests_result = MagicMock()
        interests_result.all.return_value = [("tech",)]
        sources_result = MagicMock()
        sources_result.all.return_value = [(no_match, 10), (match, 1)]

        session.execute = AsyncMock(
            side_effect=[followed_result, interests_result, sources_result]
        )

        service = PepiteService(session)
        results = await service.get_pepites_for_user(str(uuid4()), limit=2)
        assert [r.name for r in results] == ["Match", "NoMatch"]

    @pytest.mark.asyncio
    async def test_touches_last_shown_on_non_empty_result(self):
        session = AsyncMock()
        src = _mk_source(name="One")

        perso = SimpleNamespace(
            pepite_carousel_last_shown_at=None,
            pepite_carousel_dismissed_at=None,
            muted_sources=[],
        )
        session.scalar = AsyncMock(return_value=perso)
        session.add = MagicMock()
        session.flush = AsyncMock()

        followed_result = MagicMock()
        followed_result.scalars.return_value.all.return_value = []
        interests_result = MagicMock()
        interests_result.all.return_value = []
        sources_result = MagicMock()
        sources_result.all.return_value = [(src, 0)]

        session.execute = AsyncMock(
            side_effect=[followed_result, interests_result, sources_result]
        )

        service = PepiteService(session)
        results = await service.get_pepites_for_user(str(uuid4()))
        assert results
        assert perso.pepite_carousel_last_shown_at is not None
        session.flush.assert_awaited()


class TestDismiss:
    @pytest.mark.asyncio
    async def test_dismiss_creates_personalization_when_missing(self):
        session = AsyncMock()
        session.scalar = AsyncMock(return_value=None)
        session.add = MagicMock()
        session.flush = AsyncMock()

        service = PepiteService(session)
        await service.dismiss_pepite_carousel(str(uuid4()))

        session.add.assert_called_once()
        created = session.add.call_args.args[0]
        assert created.pepite_carousel_dismissed_at is not None
        session.flush.assert_awaited_once()

    @pytest.mark.asyncio
    async def test_dismiss_updates_existing_personalization(self):
        session = AsyncMock()
        old_ts = _now() - timedelta(days=30)
        perso = SimpleNamespace(pepite_carousel_dismissed_at=old_ts)
        session.scalar = AsyncMock(return_value=perso)
        session.add = MagicMock()
        session.flush = AsyncMock()

        service = PepiteService(session)
        await service.dismiss_pepite_carousel(str(uuid4()))

        session.add.assert_not_called()
        assert perso.pepite_carousel_dismissed_at > old_ts
        session.flush.assert_awaited_once()
