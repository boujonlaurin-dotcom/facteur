"""Tests for PepiteService (Story 13.2 — Feed Pepites Carousel).

Mock-based tests (no DB required) covering:
- Adaptive rate-limit by followed-source palier
- Cool-down predicate (dismiss)
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
    HIGH_SOURCES_THRESHOLD,
    LOW_SOURCES_THRESHOLD,
    RATE_LIMIT_HOURS_HIGH,
    RATE_LIMIT_HOURS_LOW,
    RATE_LIMIT_HOURS_MEDIUM,
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


class TestRateLimitHours:
    """Adaptive rate-limit window per followed-source palier."""

    def test_low_palier_24h(self):
        assert PepiteService._rate_limit_hours(0) == RATE_LIMIT_HOURS_LOW
        assert (
            PepiteService._rate_limit_hours(LOW_SOURCES_THRESHOLD - 1)
            == RATE_LIMIT_HOURS_LOW
        )

    def test_medium_palier_7d(self):
        assert (
            PepiteService._rate_limit_hours(LOW_SOURCES_THRESHOLD)
            == RATE_LIMIT_HOURS_MEDIUM
        )
        assert (
            PepiteService._rate_limit_hours(HIGH_SOURCES_THRESHOLD - 1)
            == RATE_LIMIT_HOURS_MEDIUM
        )

    def test_high_palier_14d(self):
        assert (
            PepiteService._rate_limit_hours(HIGH_SOURCES_THRESHOLD)
            == RATE_LIMIT_HOURS_HIGH
        )
        assert (
            PepiteService._rate_limit_hours(HIGH_SOURCES_THRESHOLD * 10)
            == RATE_LIMIT_HOURS_HIGH
        )


class TestRateLimitPredicate:
    def test_not_rate_limited_when_personalization_none(self):
        assert PepiteService._rate_limited(None, source_count=0) is False

    def test_not_rate_limited_when_last_shown_none(self):
        perso = SimpleNamespace(pepite_carousel_last_shown_at=None)
        assert PepiteService._rate_limited(perso, source_count=5) is False

    def test_rate_limited_recent_low_palier(self):
        perso = SimpleNamespace(
            pepite_carousel_last_shown_at=_now() - timedelta(hours=1),
        )
        assert PepiteService._rate_limited(perso, source_count=5) is True

    def test_not_rate_limited_past_24h_low_palier(self):
        perso = SimpleNamespace(
            pepite_carousel_last_shown_at=_now()
            - timedelta(hours=RATE_LIMIT_HOURS_LOW + 1),
        )
        assert PepiteService._rate_limited(perso, source_count=5) is False

    def test_handles_naive_datetime(self):
        naive = datetime.utcnow() - timedelta(hours=1)
        perso = SimpleNamespace(pepite_carousel_last_shown_at=naive)
        assert PepiteService._rate_limited(perso, source_count=5) is True

    def test_medium_palier_blocks_for_7_days(self):
        perso = SimpleNamespace(
            pepite_carousel_last_shown_at=_now() - timedelta(days=6),
        )
        # 20 sources → 7d window → still blocked at 6d
        assert PepiteService._rate_limited(perso, source_count=30) is True
        # But <20 sources → 24h window → not blocked at 6d
        assert PepiteService._rate_limited(perso, source_count=5) is False

    def test_high_palier_blocks_for_14_days(self):
        perso = SimpleNamespace(
            pepite_carousel_last_shown_at=_now() - timedelta(days=10),
        )
        # 100 sources → 14d window → still blocked at 10d
        assert PepiteService._rate_limited(perso, source_count=100) is True
        # 30 sources → 7d window → not blocked at 10d
        assert PepiteService._rate_limited(perso, source_count=30) is False


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
    async def test_blocked_by_cool_down_short_circuits_without_count_query(self):
        session = AsyncMock()
        perso = SimpleNamespace(
            pepite_carousel_last_shown_at=None,
            pepite_carousel_dismissed_at=_now() - timedelta(days=1),
        )
        session.scalar = AsyncMock(return_value=perso)
        session.execute = AsyncMock()

        service = PepiteService(session)
        assert await service.should_show_pepite_carousel(str(uuid4())) is False
        session.execute.assert_not_called()  # cool-down short-circuits

    @pytest.mark.asyncio
    async def test_blocked_by_rate_limit_low_palier(self):
        session = AsyncMock()
        perso = SimpleNamespace(
            pepite_carousel_last_shown_at=_now() - timedelta(hours=1),
            pepite_carousel_dismissed_at=None,
        )
        session.scalar = AsyncMock(return_value=perso)
        count_result = MagicMock()
        count_result.scalar.return_value = 5
        session.execute = AsyncMock(return_value=count_result)

        service = PepiteService(session)
        assert await service.should_show_pepite_carousel(str(uuid4())) is False

    @pytest.mark.asyncio
    async def test_blocked_by_rate_limit_high_palier_after_10_days(self):
        """Compte avec 60 sources → rate-limit 14j. Last shown 10j ago → bloqué."""
        session = AsyncMock()
        perso = SimpleNamespace(
            pepite_carousel_last_shown_at=_now() - timedelta(days=10),
            pepite_carousel_dismissed_at=None,
        )
        session.scalar = AsyncMock(return_value=perso)
        count_result = MagicMock()
        count_result.scalar.return_value = 60
        session.execute = AsyncMock(return_value=count_result)

        service = PepiteService(session)
        assert await service.should_show_pepite_carousel(str(uuid4())) is False

    @pytest.mark.asyncio
    async def test_allows_when_no_personalization_and_any_source_count(self):
        session = AsyncMock()
        session.scalar = AsyncMock(return_value=None)
        count_result = MagicMock()
        count_result.scalar.return_value = 100
        session.execute = AsyncMock(return_value=count_result)

        service = PepiteService(session)
        assert await service.should_show_pepite_carousel(str(uuid4())) is True

    @pytest.mark.asyncio
    async def test_allows_when_past_rate_limit_window_for_palier(self):
        """Compte 30 sources → 7j window. Last shown 8j ago → autorisé."""
        session = AsyncMock()
        perso = SimpleNamespace(
            pepite_carousel_last_shown_at=_now() - timedelta(days=8),
            pepite_carousel_dismissed_at=None,
        )
        session.scalar = AsyncMock(return_value=perso)
        count_result = MagicMock()
        count_result.scalar.return_value = 30
        session.execute = AsyncMock(return_value=count_result)

        service = PepiteService(session)
        assert await service.should_show_pepite_carousel(str(uuid4())) is True


class TestSelection:
    @pytest.mark.asyncio
    async def test_returns_empty_when_rate_limited(self):
        """Rate-limited → empty."""
        session = AsyncMock()
        perso = SimpleNamespace(
            pepite_carousel_last_shown_at=_now() - timedelta(hours=1),
            pepite_carousel_dismissed_at=None,
        )
        session.scalar = AsyncMock(return_value=perso)
        count_result = MagicMock()
        count_result.scalar.return_value = 5  # low palier → 24h window
        session.execute = AsyncMock(return_value=count_result)

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
        # 1. _source_count (should_show_pepite_carousel)
        # 2. followed IDs
        # 3. interest slugs
        # 4. candidate query
        count_result = MagicMock()
        count_result.scalar.return_value = 5
        followed_result = MagicMock()
        followed_result.scalars.return_value.all.return_value = [followed_id]
        interests_result = MagicMock()
        interests_result.all.return_value = []
        sources_result = MagicMock()
        sources_result.all.return_value = [(visible, 3)]

        session.execute = AsyncMock(
            side_effect=[
                count_result,
                followed_result,
                interests_result,
                sources_result,
            ]
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

        count_result = MagicMock()
        count_result.scalar.return_value = 5
        followed_result = MagicMock()
        followed_result.scalars.return_value.all.return_value = []
        interests_result = MagicMock()
        interests_result.all.return_value = [("tech",)]
        # Return no_match FIRST in raw SQL result — should be reordered by sort
        sources_result = MagicMock()
        sources_result.all.return_value = [(no_match, 10), (match, 1)]

        session.execute = AsyncMock(
            side_effect=[
                count_result,
                followed_result,
                interests_result,
                sources_result,
            ]
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

        count_result = MagicMock()
        count_result.scalar.return_value = 0
        followed_result = MagicMock()
        followed_result.scalars.return_value.all.return_value = []
        interests_result = MagicMock()
        interests_result.all.return_value = []
        sources_result = MagicMock()
        sources_result.all.return_value = [(src, 0)]

        session.execute = AsyncMock(
            side_effect=[
                count_result,
                followed_result,
                interests_result,
                sources_result,
            ]
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
