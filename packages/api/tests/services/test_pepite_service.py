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

from app.models.enums import BiasStance, ReliabilityScore, SourceType
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
    source_type=SourceType.ARTICLE,
    reliability_score=ReliabilityScore.HIGH,
    bias_stance=BiasStance.CENTER,
):
    return SimpleNamespace(
        id=source_id or uuid4(),
        name=name,
        url=f"https://{name.lower().replace(' ', '')}.example.com",
        type=source_type,
        theme=theme,
        description=None,
        logo_url=None,
        is_curated=is_curated,
        is_active=True,
        is_pepite_recommendation=True,
        pepite_for_themes=pepite_for_themes,
        bias_stance=bias_stance,
        reliability_score=reliability_score,
        bias_origin=SimpleNamespace(value="unknown"),
        secondary_themes=None,
        granular_topics=None,
        source_tier="mainstream",
        score_independence=None,
        score_rigor=None,
        score_ux=None,
    )


def _freshness_result(*sources, days_ago=1):
    """MagicMock result for `fetch_last_published`.

    Chaque source reçoit un dernier article à `days_ago` jours (fraîche par
    défaut). Une source absente ⇒ aucun article ⇒ feed mort pour `classify`.
    """
    result = MagicMock()
    last = _now() - timedelta(days=days_ago)
    result.all.return_value = [(s.id, last) for s in sources]
    return result


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
    async def test_force_show_bypasses_cool_down_without_touching_last_shown(self):
        session = AsyncMock()
        old_last_shown = _now() - timedelta(hours=1)
        src = _mk_source(name="Forced")
        perso = SimpleNamespace(
            pepite_carousel_last_shown_at=old_last_shown,
            pepite_carousel_dismissed_at=_now() - timedelta(days=1),
            muted_sources=[],
        )
        session.scalar = AsyncMock(return_value=perso)
        session.flush = AsyncMock()

        followed_result = MagicMock()
        followed_result.scalars.return_value.all.return_value = []
        interests_result = MagicMock()
        interests_result.all.return_value = []
        sources_result = MagicMock()
        sources_result.all.return_value = [(src, 0)]
        session.execute = AsyncMock(
            side_effect=[
                followed_result,
                interests_result,
                sources_result,
                _freshness_result(src),
            ]
        )

        service = PepiteService(session)
        results = await service.get_pepites_for_user(str(uuid4()), force_show=True)

        assert [r.name for r in results] == ["Forced"]
        assert perso.pepite_carousel_last_shown_at == old_last_shown
        session.flush.assert_not_awaited()

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
            side_effect=[
                followed_result,
                interests_result,
                sources_result,
                _freshness_result(visible),
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

        followed_result = MagicMock()
        followed_result.scalars.return_value.all.return_value = []
        interests_result = MagicMock()
        interests_result.all.return_value = [("tech",)]
        sources_result = MagicMock()
        sources_result.all.return_value = [(no_match, 10), (match, 1)]

        session.execute = AsyncMock(
            side_effect=[
                followed_result,
                interests_result,
                sources_result,
                _freshness_result(no_match, match),
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

        followed_result = MagicMock()
        followed_result.scalars.return_value.all.return_value = []
        interests_result = MagicMock()
        interests_result.all.return_value = []
        sources_result = MagicMock()
        sources_result.all.return_value = [(src, 0)]

        session.execute = AsyncMock(
            side_effect=[
                followed_result,
                interests_result,
                sources_result,
                _freshness_result(src),
            ]
        )

        service = PepiteService(session)
        results = await service.get_pepites_for_user(str(uuid4()))
        assert results
        assert perso.pepite_carousel_last_shown_at is not None
        session.flush.assert_awaited()


class TestSafetyGateAndFreshness:
    """Le carrousel Pépites applique le gate de sécurité + le filtre fraîcheur."""

    def _wire(self, session, rows, freshness):
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
        sources_result.all.return_value = rows
        session.execute = AsyncMock(
            side_effect=[
                followed_result,
                interests_result,
                sources_result,
                freshness,
            ]
        )

    @pytest.mark.asyncio
    async def test_excludes_alternative_bias_source(self):
        session = AsyncMock()
        alt = _mk_source(name="Limit", bias_stance=BiasStance.ALTERNATIVE)
        ok = _mk_source(name="Vert")
        self._wire(session, [(alt, 5), (ok, 5)], _freshness_result(alt, ok))

        service = PepiteService(session)
        results = await service.get_pepites_for_user(str(uuid4()), limit=4)
        assert [r.name for r in results] == ["Vert"]

    @pytest.mark.asyncio
    async def test_excludes_unknown_reliability_source(self):
        session = AsyncMock()
        unknown = _mk_source(
            name="Les Lueurs", reliability_score=ReliabilityScore.UNKNOWN
        )
        ok = _mk_source(name="Vert")
        self._wire(session, [(unknown, 5), (ok, 5)], _freshness_result(unknown, ok))

        service = PepiteService(session)
        results = await service.get_pepites_for_user(str(uuid4()), limit=4)
        assert [r.name for r in results] == ["Vert"]

    @pytest.mark.asyncio
    async def test_excludes_dead_article_feed(self):
        session = AsyncMock()
        dead = _mk_source(name="StreetPress", source_type=SourceType.ARTICLE)
        alive = _mk_source(name="Vert", source_type=SourceType.ARTICLE)
        # `dead` absente du résultat fraîcheur ⇒ 0/0 ⇒ feed mort exclu.
        self._wire(session, [(dead, 5), (alive, 5)], _freshness_result(alive))

        service = PepiteService(session)
        results = await service.get_pepites_for_user(str(uuid4()), limit=4)
        assert [r.name for r in results] == ["Vert"]

    @pytest.mark.asyncio
    async def test_slow_podcast_kept_but_downgraded(self):
        session = AsyncMock()
        # Podcast sans article sur 30j mais actif sur 90j ⇒ conservé, déclassé.
        slow = _mk_source(name="Monsieur Phi", source_type=SourceType.PODCAST)
        fresh = _mk_source(name="Next.ink", source_type=SourceType.ARTICLE)
        freshness = MagicMock()
        freshness.all.return_value = [
            (slow.id, _now() - timedelta(days=45)),  # silencieux 30j, actif 90j
            (fresh.id, _now() - timedelta(days=1)),
        ]
        # slow a plus de followers → sans déclassement il passerait devant.
        self._wire(session, [(slow, 99), (fresh, 1)], freshness)

        service = PepiteService(session)
        results = await service.get_pepites_for_user(str(uuid4()), limit=4)
        assert [r.name for r in results] == ["Next.ink", "Monsieur Phi"]


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
