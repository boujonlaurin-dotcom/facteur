"""Tests unitaires pour DigestService — actions et complétion.

Couvre:
- apply_action: gestion des actions READ, SAVE, NOT_INTERESTED, UNDO
- complete_digest: enregistrement de complétion et stats
- _get_existing_digest: vérification d'existence de digest

Note: Ces tests mockent la session DB et les dépendances internes.
Ils vérifient le comportement logique, pas l'intégration DB.
"""

import contextlib
from datetime import date, datetime, timedelta
from unittest.mock import AsyncMock, Mock, patch
from uuid import uuid4

import pytest

from app.models.enums import ContentStatus
from app.schemas.digest import DigestAction

# ─── Fixtures ─────────────────────────────────────────────────────────────────


@pytest.fixture
def mock_session():
    """Mock de session SQLAlchemy async."""
    session = AsyncMock()
    session.flush = AsyncMock()
    session.add = Mock()
    session.scalar = AsyncMock(return_value=None)
    session.execute = AsyncMock()
    session.get = AsyncMock(return_value=None)
    return session


@pytest.fixture
def service(mock_session):
    """Instance de DigestService avec toutes les dépendances mockées."""
    with (
        patch("app.services.digest_service.DigestSelector"),
        patch("app.services.digest_service.StreakService") as mock_streak_cls,
    ):
        mock_streak = Mock()
        mock_streak.increment_consumption = AsyncMock()
        mock_streak_cls.return_value = mock_streak

        from app.services.digest_service import DigestService

        svc = DigestService(mock_session)
        svc.streak_service = mock_streak

    return svc


# ─── Tests: apply_action ──────────────────────────────────────────────────────


class TestApplyAction:
    """Tests pour DigestService.apply_action()."""

    @pytest.mark.asyncio
    async def test_read_action_marks_consumed(self, service, mock_session):
        """READ action sets content status to CONSUMED."""
        digest_id = uuid4()
        user_id = uuid4()
        content_id = uuid4()

        # Mock _get_or_create_content_status returns a mock status
        mock_status = Mock()
        mock_status.status = ContentStatus.UNSEEN
        mock_status.is_saved = False
        mock_status.is_hidden = False
        mock_status.hidden_reason = None

        with patch.object(
            service,
            "_get_or_create_content_status",
            new_callable=AsyncMock,
            return_value=mock_status,
        ):
            result = await service.apply_action(
                digest_id=digest_id,
                user_id=user_id,
                content_id=content_id,
                action=DigestAction.READ,
            )

        assert result["success"] is True
        assert result["action"] == DigestAction.READ
        assert result["content_id"] == content_id
        assert mock_status.status == ContentStatus.CONSUMED
        assert mock_status.is_hidden is False

    @pytest.mark.asyncio
    async def test_save_action_sets_saved(self, service, mock_session):
        """SAVE action sets is_saved to True."""
        mock_status = Mock()
        mock_status.status = ContentStatus.UNSEEN
        mock_status.is_saved = False
        mock_status.is_hidden = False
        mock_status.saved_at = None

        with patch.object(
            service,
            "_get_or_create_content_status",
            new_callable=AsyncMock,
            return_value=mock_status,
        ):
            result = await service.apply_action(
                digest_id=uuid4(),
                user_id=uuid4(),
                content_id=uuid4(),
                action=DigestAction.SAVE,
            )

        assert result["success"] is True
        assert mock_status.is_saved is True
        assert mock_status.is_hidden is False
        assert mock_status.saved_at is not None

    @pytest.mark.asyncio
    async def test_not_interested_hides_content(self, service, mock_session):
        """NOT_INTERESTED action hides the content and triggers mute."""
        mock_status = Mock()
        mock_status.status = ContentStatus.UNSEEN
        mock_status.is_saved = False
        mock_status.is_hidden = False
        mock_status.hidden_reason = None

        with (
            patch.object(
                service,
                "_get_or_create_content_status",
                new_callable=AsyncMock,
                return_value=mock_status,
            ),
            patch.object(
                service, "_trigger_personalization_mute", new_callable=AsyncMock
            ) as mock_mute,
        ):
            result = await service.apply_action(
                digest_id=uuid4(),
                user_id=uuid4(),
                content_id=uuid4(),
                action=DigestAction.NOT_INTERESTED,
            )

        assert result["success"] is True
        assert mock_status.is_hidden is True
        assert mock_status.hidden_reason == "not_interested"
        mock_mute.assert_awaited_once()

    @pytest.mark.asyncio
    async def test_undo_resets_all_states(self, service, mock_session):
        """UNDO action resets status to UNSEEN and clears all flags."""
        mock_status = Mock()
        mock_status.status = ContentStatus.CONSUMED
        mock_status.is_saved = True
        mock_status.is_hidden = True
        mock_status.hidden_reason = "not_interested"

        with patch.object(
            service,
            "_get_or_create_content_status",
            new_callable=AsyncMock,
            return_value=mock_status,
        ):
            result = await service.apply_action(
                digest_id=uuid4(),
                user_id=uuid4(),
                content_id=uuid4(),
                action=DigestAction.UNDO,
            )

        assert result["success"] is True
        assert mock_status.status == ContentStatus.UNSEEN
        assert mock_status.is_saved is False
        assert mock_status.is_hidden is False
        assert mock_status.hidden_reason is None

    @pytest.mark.asyncio
    async def test_action_returns_applied_at_timestamp(self, service, mock_session):
        """Result includes applied_at timestamp."""
        mock_status = Mock()
        mock_status.status = ContentStatus.UNSEEN
        mock_status.is_saved = False
        mock_status.is_hidden = False

        with patch.object(
            service,
            "_get_or_create_content_status",
            new_callable=AsyncMock,
            return_value=mock_status,
        ):
            result = await service.apply_action(
                digest_id=uuid4(),
                user_id=uuid4(),
                content_id=uuid4(),
                action=DigestAction.READ,
            )

        assert "applied_at" in result
        assert isinstance(result["applied_at"], datetime)


# ─── Tests: complete_digest ───────────────────────────────────────────────────


class TestCompleteDigest:
    """Tests pour DigestService.complete_digest()."""

    @pytest.mark.asyncio
    async def test_complete_returns_success(self, service, mock_session):
        """Completing a digest returns success with stats."""
        digest_id = uuid4()
        user_id = uuid4()

        # Mock the digest lookup
        mock_digest = Mock()
        mock_digest.id = digest_id
        mock_digest.target_date = date.today()
        mock_digest.items = [
            {"content_id": str(uuid4()), "rank": i, "reason": "test"}
            for i in range(1, 6)
        ]
        mock_session.get = AsyncMock(return_value=mock_digest)

        # Mock action stats
        with (
            patch.object(
                service,
                "_get_digest_action_stats",
                new_callable=AsyncMock,
                return_value={"read": 3, "saved": 1, "dismissed": 1},
            ),
            patch.object(
                service,
                "_update_closure_streak",
                new_callable=AsyncMock,
                return_value={
                    "current": 5,
                    "longest": 10,
                    "message": "Série de 5 jours !",
                },
            ),
        ):
            result = await service.complete_digest(
                digest_id=digest_id, user_id=user_id, closure_time_seconds=120
            )

        assert result["success"] is True
        assert result["digest_id"] == digest_id
        assert result["articles_read"] == 3
        assert result["articles_saved"] == 1
        assert result["articles_dismissed"] == 1
        assert result["closure_time_seconds"] == 120
        assert result["closure_streak"] == 5
        assert result["streak_message"] == "Série de 5 jours !"

    @pytest.mark.asyncio
    async def test_complete_nonexistent_digest_raises(self, service, mock_session):
        """Completing a nonexistent digest raises ValueError."""
        mock_session.get = AsyncMock(return_value=None)

        with pytest.raises(ValueError, match="Digest not found"):
            await service.complete_digest(digest_id=uuid4(), user_id=uuid4())

    @pytest.mark.asyncio
    async def test_complete_adds_completion_record(self, service, mock_session):
        """Completing a digest adds a DigestCompletion to the session."""
        digest_id = uuid4()
        user_id = uuid4()

        mock_digest = Mock()
        mock_digest.id = digest_id
        mock_digest.target_date = date.today()
        mock_digest.items = []
        mock_session.get = AsyncMock(return_value=mock_digest)

        with (
            patch.object(
                service,
                "_get_digest_action_stats",
                new_callable=AsyncMock,
                return_value={"read": 0, "saved": 0, "dismissed": 0},
            ),
            patch.object(
                service,
                "_update_closure_streak",
                new_callable=AsyncMock,
                return_value={
                    "current": 1,
                    "longest": 1,
                    "message": "Premier digest complété !",
                },
            ),
        ):
            await service.complete_digest(
                digest_id=digest_id, user_id=user_id, closure_time_seconds=60
            )

        # Verify session.add was called with a DigestCompletion instance
        mock_session.add.assert_called_once()
        added_obj = mock_session.add.call_args[0][0]
        from app.models.digest_completion import DigestCompletion

        assert isinstance(added_obj, DigestCompletion)
        assert added_obj.user_id == user_id
        assert added_obj.target_date == date.today()


# ─── Tests: get_or_create_digest fallback J-1 ────────────────────────────────


class TestFallbackYesterday:
    """Tests pour le fallback J-1 dans get_or_create_digest()."""

    @pytest.mark.asyncio
    async def test_fallback_yesterday_digest_when_today_missing(
        self, service, mock_session
    ):
        """When no digest exists for today, serve yesterday's digest."""
        user_id = uuid4()
        today = date.today()
        yesterday = today - timedelta(days=1)

        mock_yesterday_digest = Mock()
        mock_yesterday_digest.id = uuid4()
        mock_yesterday_digest.target_date = yesterday
        mock_yesterday_digest.format_version = "editorial_v1"

        mock_response = Mock()

        # _get_existing_digest returns None for today, a digest for yesterday
        async def fake_get_existing(uid, d, is_serene=False):
            if d == today:
                return None
            if d == yesterday:
                return mock_yesterday_digest
            return None

        mock_build = AsyncMock(return_value=mock_response)

        with (
            patch("app.services.user_service.UserService") as mock_user_svc_cls,
            patch.object(
                service, "_get_existing_digest", side_effect=fake_get_existing
            ),
            patch.object(service, "_build_digest_response", mock_build),
            patch.object(
                service,
                "_get_user_digest_format",
                new_callable=AsyncMock,
                return_value="editorial",
            ),
        ):
            mock_user_svc_cls.return_value.get_or_create_profile = AsyncMock()
            result = await service.get_or_create_digest(
                user_id=user_id, target_date=today
            )

        assert result is mock_response
        mock_build.assert_awaited_once_with(mock_yesterday_digest, user_id)

    @pytest.mark.asyncio
    async def test_no_fallback_when_force_regenerate(self, service, mock_session):
        """force_regenerate=True should NOT serve J-1, should proceed to generation."""
        user_id = uuid4()
        today = date.today()

        call_count = 0

        async def fake_get_existing(uid, d, is_serene=False):
            nonlocal call_count
            call_count += 1
            return None

        with (
            patch("app.services.user_service.UserService") as mock_user_svc_cls,
            patch.object(
                service, "_get_existing_digest", side_effect=fake_get_existing
            ),
            patch.object(
                service,
                "_get_user_digest_format",
                new_callable=AsyncMock,
                return_value="topics",
            ),
        ):
            mock_user_svc_cls.return_value.get_or_create_profile = AsyncMock()
            with contextlib.suppress(Exception):
                await service.get_or_create_digest(
                    user_id=user_id, target_date=today, force_regenerate=True
                )

        # _get_existing_digest should only be called once (for today), not for yesterday
        assert call_count == 1

    @pytest.mark.asyncio
    async def test_fallback_skipped_when_yesterday_also_missing(
        self, service, mock_session
    ):
        """When both today and yesterday have no digest, proceed to generation."""
        user_id = uuid4()
        today = date.today()

        with (
            patch("app.services.user_service.UserService") as mock_user_svc_cls,
            patch.object(
                service,
                "_get_existing_digest",
                new_callable=AsyncMock,
                return_value=None,
            ),
            patch.object(
                service,
                "_get_user_digest_format",
                new_callable=AsyncMock,
                return_value="topics",
            ),
            patch.object(
                service, "_build_digest_response", new_callable=AsyncMock
            ) as mock_build,
        ):
            mock_user_svc_cls.return_value.get_or_create_profile = AsyncMock()
            with contextlib.suppress(Exception):
                await service.get_or_create_digest(user_id=user_id, target_date=today)

        # _build_digest_response should NOT have been called (no yesterday digest to serve)
        mock_build.assert_not_awaited()

    @pytest.mark.asyncio
    async def test_stale_fallback_sets_is_stale_flag_and_schedules_regen(
        self, service, mock_session
    ):
        """Yesterday fallback must set is_stale_fallback=True AND schedule bg regen."""
        from app.schemas.digest import DigestResponse

        user_id = uuid4()
        today = date.today()
        yesterday = today - timedelta(days=1)

        mock_yesterday_digest = Mock()
        mock_yesterday_digest.id = uuid4()
        mock_yesterday_digest.target_date = yesterday
        mock_yesterday_digest.format_version = "editorial_v1"

        # Build a real DigestResponse so we can observe is_stale_fallback
        response = DigestResponse(
            digest_id=uuid4(),
            user_id=user_id,
            target_date=yesterday,
            generated_at=datetime.utcnow(),
            items=[],
        )

        async def fake_get_existing(uid, d, is_serene=False):
            if d == today:
                return None
            if d == yesterday:
                return mock_yesterday_digest
            return None

        with (
            patch("app.services.user_service.UserService") as mock_user_svc_cls,
            patch.object(
                service, "_get_existing_digest", side_effect=fake_get_existing
            ),
            patch.object(
                service,
                "_build_digest_response",
                new_callable=AsyncMock,
                return_value=response,
            ),
            patch.object(
                service,
                "_get_user_digest_format",
                new_callable=AsyncMock,
                return_value="editorial",
            ),
            patch(
                "app.services.digest_service._schedule_background_regen"
            ) as mock_schedule,
        ):
            mock_user_svc_cls.return_value.get_or_create_profile = AsyncMock()
            result = await service.get_or_create_digest(
                user_id=user_id, target_date=today
            )

        assert result is not None
        assert result.is_stale_fallback is True
        mock_schedule.assert_called_once()
        # Check kwargs were forwarded correctly
        call_kwargs = mock_schedule.call_args.kwargs
        assert call_kwargs["user_id"] == user_id
        assert call_kwargs["target_date"] == today
        assert call_kwargs["is_serene"] is False


# ─── Tests: background regen rate limiting ────────────────────────────────────


class TestBackgroundRegenRateLimit:
    """_schedule_background_regen enforces one spawn per minute per key."""

    def test_rate_limit_blocks_repeat_calls_within_cooldown(self):
        """Second call within cooldown window is a no-op."""
        from app.services import digest_service

        # Reset rate limit dict
        digest_service._BG_REGEN_RATE_LIMIT.clear()

        user_id = uuid4()
        target_date = date.today()

        with patch("asyncio.create_task") as mock_create_task:
            digest_service._schedule_background_regen(
                user_id=user_id, target_date=target_date, is_serene=False
            )
            digest_service._schedule_background_regen(
                user_id=user_id, target_date=target_date, is_serene=False
            )
            # First call spawned a task; second was blocked by rate limit
            assert mock_create_task.call_count == 1

    def test_rate_limit_independent_per_serene_variant(self):
        """(user, date, False) and (user, date, True) are separate buckets."""
        from app.services import digest_service

        digest_service._BG_REGEN_RATE_LIMIT.clear()

        user_id = uuid4()
        target_date = date.today()

        with patch("asyncio.create_task") as mock_create_task:
            digest_service._schedule_background_regen(
                user_id=user_id, target_date=target_date, is_serene=False
            )
            digest_service._schedule_background_regen(
                user_id=user_id, target_date=target_date, is_serene=True
            )
            # Both should go through — different variants
            assert mock_create_task.call_count == 2


# ─── Tests: Phase 5.2 — deferred stale-format deletion ────────────────────────


class TestDeferredStaleFormatDeletion:
    """Stale-format digest should only be deleted after new one succeeds."""

    @pytest.mark.asyncio
    async def test_stale_format_not_deleted_on_generation_failure(
        self, service, mock_session
    ):
        """When generation returns nothing, stale-format digest survives and is served."""
        from app.schemas.digest import DigestResponse

        user_id = uuid4()
        today = date.today()

        stale_digest = Mock()
        stale_digest.id = uuid4()
        stale_digest.target_date = today
        stale_digest.format_version = "flat_v1"  # wrong format
        stale_digest.user_id = user_id
        stale_digest.is_serene = False

        response = DigestResponse(
            digest_id=stale_digest.id,
            user_id=user_id,
            target_date=today,
            generated_at=datetime.utcnow(),
            items=[],
            format_version="flat_v1",
        )

        async def fake_get_existing(uid, d, is_serene=False):
            if d == today:
                return stale_digest
            return None

        # Selector returns nothing → generation failure
        service.selector = Mock()
        service.selector.select_for_user = AsyncMock(return_value=[])

        # sensitive_themes lookup is a session.execute(...) + scalar_one_or_none().
        # AsyncMock children default to AsyncMock, so scalar_one_or_none() would
        # return a coroutine. Wire a sync Mock result so the code sees None.
        _prefs_result = Mock()
        _prefs_result.scalar_one_or_none = Mock(return_value=None)
        mock_session.execute.return_value = _prefs_result

        async def fake_emergency(*args, **kwargs):
            return []

        with (
            patch("app.services.user_service.UserService") as mock_user_svc_cls,
            patch.object(
                service, "_get_existing_digest", side_effect=fake_get_existing
            ),
            patch.object(
                service,
                "_get_user_digest_format",
                new_callable=AsyncMock,
                return_value="editorial",
            ),
            patch.object(
                service,
                "_get_emergency_candidates",
                new_callable=AsyncMock,
                return_value=[],
            ),
            patch.object(
                service,
                "_build_digest_response",
                new_callable=AsyncMock,
                return_value=response,
            ),
        ):
            mock_user_svc_cls.return_value.get_or_create_profile = AsyncMock()
            result = await service.get_or_create_digest(
                user_id=user_id, target_date=today, force_regenerate=True
            )

        # Stale digest should have been returned as last-resort fallback
        assert result is not None
        # session.delete should never have been called on the stale digest
        # (we only delete it AFTER we have items to store)
        for call in mock_session.delete.call_args_list:
            assert call.args[0] is not stale_digest


# ─── Tests: render-failure graceful fallback (Fix 2) ──────────────────────────


class TestRenderFailureFallback:
    """A corrupted existing digest must not cause an infinite 503 loop.

    Prior behaviour (PR #381): if ``_build_digest_response`` raised for an
    ``editorial_v1`` / ``topics_v1`` record, the service re-raised. With the
    digest still in DB, every subsequent request hit the same broken JSONB
    and failed — a user was locked out for the whole day.

    New behaviour: treat it like a stale-format record. Defer deletion, fall
    through to regeneration, and let the deferred-delete logic replace the
    corrupted record once a fresh one is ready.
    """

    @pytest.mark.asyncio
    async def test_modern_format_render_failure_falls_through_to_regen(
        self, service, mock_session
    ):
        """If editorial_v1 render fails, selector must still be invoked."""
        from app.schemas.digest import DigestResponse

        user_id = uuid4()
        today = date.today()

        corrupted = Mock()
        corrupted.id = uuid4()
        corrupted.target_date = today
        corrupted.format_version = "editorial_v1"
        corrupted.user_id = user_id
        corrupted.is_serene = False

        fresh_response = DigestResponse(
            digest_id=uuid4(),
            user_id=user_id,
            target_date=today,
            generated_at=datetime.utcnow(),
            items=[],
            format_version="editorial_v1",
        )

        async def fake_get_existing(uid, d, is_serene=False):
            # Today's corrupted digest is returned once; no yesterday digest.
            if d == today:
                return corrupted
            return None

        # Selector returns an empty list — enough to reach the emergency/
        # stale-fallback branches without crashing. The key assertion is
        # that selector is INVOKED: that proves we fell through instead of
        # raising.
        service.selector = Mock()
        service.selector.select_for_user = AsyncMock(return_value=[])

        _prefs_result = Mock()
        _prefs_result.scalar_one_or_none = Mock(return_value=None)
        mock_session.execute.return_value = _prefs_result

        call_log: list[str] = []

        async def fake_build(digest, user_id):
            if digest is corrupted:
                call_log.append("corrupted")
                raise KeyError("actu_article")
            call_log.append("fresh")
            return fresh_response

        with (
            patch("app.services.user_service.UserService") as mock_user_svc_cls,
            patch.object(
                service, "_get_existing_digest", side_effect=fake_get_existing
            ),
            patch.object(
                service,
                "_get_user_digest_format",
                new_callable=AsyncMock,
                return_value="editorial",
            ),
            patch.object(
                service,
                "_get_emergency_candidates",
                new_callable=AsyncMock,
                return_value=[],
            ),
            patch.object(service, "_build_digest_response", side_effect=fake_build),
        ):
            mock_user_svc_cls.return_value.get_or_create_profile = AsyncMock()
            result = await service.get_or_create_digest(
                user_id=user_id, target_date=today
            )

        # Selector ran → we did not re-raise the KeyError.
        service.selector.select_for_user.assert_awaited()
        # The first build call is for the corrupted digest. If the fix
        # regressed to `raise`, we never would have gotten here.
        assert call_log[0] == "corrupted"
        # The corrupted record is deferred-deleted (not destroyed immediately
        # on render failure). It survives when generation fails, which is
        # exactly what enables the stale-fallback to serve *something*.
        # (An exact "was/wasn't deleted" assertion depends on whether
        # generation also failed here; the key regression is the absence
        # of a re-raise, checked by reaching this line.)
        assert (
            result is None
            or result is fresh_response
            or hasattr(result, "is_stale_fallback")
        )

    @pytest.mark.asyncio
    async def test_modern_format_render_failure_does_not_delete_immediately(
        self, service, mock_session
    ):
        """The corrupted record must only be deleted after a replacement exists."""
        user_id = uuid4()
        today = date.today()

        corrupted = Mock()
        corrupted.id = uuid4()
        corrupted.target_date = today
        corrupted.format_version = "topics_v1"
        corrupted.user_id = user_id
        corrupted.is_serene = False

        async def fake_get_existing(uid, d, is_serene=False):
            if d == today:
                return corrupted
            return None

        service.selector = Mock()
        service.selector.select_for_user = AsyncMock(return_value=[])

        _prefs_result = Mock()
        _prefs_result.scalar_one_or_none = Mock(return_value=None)
        mock_session.execute.return_value = _prefs_result

        async def fake_build(digest, user_id):
            raise RuntimeError("boom")

        with (
            patch("app.services.user_service.UserService") as mock_user_svc_cls,
            patch.object(
                service, "_get_existing_digest", side_effect=fake_get_existing
            ),
            patch.object(
                service,
                "_get_user_digest_format",
                new_callable=AsyncMock,
                return_value="topics",
            ),
            patch.object(
                service,
                "_get_emergency_candidates",
                new_callable=AsyncMock,
                return_value=[],
            ),
            patch.object(service, "_build_digest_response", side_effect=fake_build),
        ):
            mock_user_svc_cls.return_value.get_or_create_profile = AsyncMock()
            await service.get_or_create_digest(user_id=user_id, target_date=today)

        # The corrupted record must survive the render failure path. The
        # previous raise-on-modern-format behaviour never reached any
        # delete logic either, but the new path must also refrain from
        # pre-emptively wiping the only digest the user has.
        for call in mock_session.delete.call_args_list:
            assert call.args[0] is not corrupted


# ─── Tests: multi-day same-variant fallback (serein regression) ────────────────


class TestRecentVariantFallback:
    """Walk back up to 7 days for a SAME-variant digest before falling through.

    Regression for the 2026-04-12 serein outage: with the old 1-day fallback,
    a single missed serein batch meant the endpoint returned None. The mobile
    client then silently rendered the pour_vous digest labelled as serein
    (see ``_activeDigest`` in digest_provider.dart). These tests lock in:

      1. We never cross-fall: a serein request never serves a pour_vous
         digest, no matter how old.
      2. We walk back multiple days to find the most recent serein digest.
      3. The served response is marked ``is_stale_fallback=True`` and
         schedules a background regen for today.
      4. Format_version ``flat_v1`` is skipped over (we'd rather walk back
         further than downgrade the user to the legacy layout).
    """

    @pytest.mark.asyncio
    async def test_serein_fallback_walks_back_multiple_days(
        self, service, mock_session
    ):
        """When yesterday has no serein digest, walk back until one is found."""
        from app.schemas.digest import DigestResponse

        user_id = uuid4()
        today = date.today()
        three_days_ago = today - timedelta(days=3)

        serein_three_days_ago = Mock()
        serein_three_days_ago.id = uuid4()
        serein_three_days_ago.target_date = three_days_ago
        serein_three_days_ago.format_version = "editorial_v1"
        serein_three_days_ago.user_id = user_id
        serein_three_days_ago.is_serene = True

        response = DigestResponse(
            digest_id=serein_three_days_ago.id,
            user_id=user_id,
            target_date=three_days_ago,
            generated_at=datetime.utcnow(),
            items=[],
            format_version="editorial_v1",
            is_serene=True,
        )

        lookup_log: list[tuple[date, bool]] = []

        async def fake_get_existing(uid, d, is_serene=False):
            lookup_log.append((d, is_serene))
            # Only the 3-days-ago serein digest exists.
            if d == three_days_ago and is_serene is True:
                return serein_three_days_ago
            return None

        with (
            patch("app.services.user_service.UserService") as mock_user_svc_cls,
            patch.object(
                service, "_get_existing_digest", side_effect=fake_get_existing
            ),
            patch.object(
                service,
                "_get_user_digest_format",
                new_callable=AsyncMock,
                return_value="editorial",
            ),
            patch.object(
                service,
                "_build_digest_response",
                new_callable=AsyncMock,
                return_value=response,
            ),
            patch(
                "app.services.digest_service._schedule_background_regen"
            ) as mock_schedule,
        ):
            mock_user_svc_cls.return_value.get_or_create_profile = AsyncMock()
            result = await service.get_or_create_digest(
                user_id=user_id, target_date=today, is_serene=True
            )

        assert result is response
        assert result.is_stale_fallback is True
        # Regen scheduled for TODAY with is_serene=True (not pour_vous).
        mock_schedule.assert_called_once()
        kwargs = mock_schedule.call_args.kwargs
        assert kwargs["target_date"] == today
        assert kwargs["is_serene"] is True
        # Every lookup passed is_serene=True — we never queried the pour_vous
        # variant during the fallback walk.
        fallback_lookups = [(d, s) for d, s in lookup_log if d != today]
        assert fallback_lookups, "expected at least one fallback lookup"
        assert all(s is True for _, s in fallback_lookups), (
            "fallback walked into pour_vous variant — should never happen"
        )

    @pytest.mark.asyncio
    async def test_serein_fallback_never_returns_pour_vous_digest(
        self, service, mock_session
    ):
        """A pour_vous digest existing for yesterday must NOT satisfy a serein request."""
        user_id = uuid4()
        today = date.today()
        yesterday = today - timedelta(days=1)

        # Only the pour_vous variant exists for yesterday; no serein digest
        # anywhere in the lookback window.
        pour_vous_yesterday = Mock()
        pour_vous_yesterday.id = uuid4()
        pour_vous_yesterday.target_date = yesterday
        pour_vous_yesterday.format_version = "editorial_v1"
        pour_vous_yesterday.user_id = user_id
        pour_vous_yesterday.is_serene = False

        async def fake_get_existing(uid, d, is_serene=False):
            # Return pour_vous ONLY when caller explicitly asks is_serene=False.
            if d == yesterday and is_serene is False:
                return pour_vous_yesterday
            return None

        service.selector = Mock()
        service.selector.select_for_user = AsyncMock(return_value=[])

        _prefs_result = Mock()
        _prefs_result.scalar_one_or_none = Mock(return_value=None)
        mock_session.execute.return_value = _prefs_result

        with (
            patch("app.services.user_service.UserService") as mock_user_svc_cls,
            patch.object(
                service, "_get_existing_digest", side_effect=fake_get_existing
            ),
            patch.object(
                service,
                "_get_user_digest_format",
                new_callable=AsyncMock,
                return_value="editorial",
            ),
            patch.object(
                service,
                "_get_emergency_candidates",
                new_callable=AsyncMock,
                return_value=[],
            ),
            patch.object(
                service, "_build_digest_response", new_callable=AsyncMock
            ) as mock_build,
        ):
            mock_user_svc_cls.return_value.get_or_create_profile = AsyncMock()
            await service.get_or_create_digest(
                user_id=user_id, target_date=today, is_serene=True
            )

        # `_build_digest_response` must never have been called with the
        # pour_vous record — even though it was the most recent digest in DB.
        for call in mock_build.call_args_list:
            served = call.args[0]
            assert served is not pour_vous_yesterday, (
                "serein request served a pour_vous digest as fallback"
            )

    @pytest.mark.asyncio
    async def test_fallback_skips_flat_v1_and_tries_older(self, service, mock_session):
        """flat_v1 candidates are skipped; walk keeps going to find a modern one."""
        from app.schemas.digest import DigestResponse

        user_id = uuid4()
        today = date.today()
        yesterday = today - timedelta(days=1)
        two_days_ago = today - timedelta(days=2)

        flat_yesterday = Mock()
        flat_yesterday.id = uuid4()
        flat_yesterday.target_date = yesterday
        flat_yesterday.format_version = "flat_v1"  # legacy — must skip
        flat_yesterday.user_id = user_id
        flat_yesterday.is_serene = True

        modern_two_days_ago = Mock()
        modern_two_days_ago.id = uuid4()
        modern_two_days_ago.target_date = two_days_ago
        modern_two_days_ago.format_version = "editorial_v1"
        modern_two_days_ago.user_id = user_id
        modern_two_days_ago.is_serene = True

        response = DigestResponse(
            digest_id=modern_two_days_ago.id,
            user_id=user_id,
            target_date=two_days_ago,
            generated_at=datetime.utcnow(),
            items=[],
            format_version="editorial_v1",
            is_serene=True,
        )

        async def fake_get_existing(uid, d, is_serene=False):
            if d == yesterday and is_serene is True:
                return flat_yesterday
            if d == two_days_ago and is_serene is True:
                return modern_two_days_ago
            return None

        built: list = []

        async def fake_build(digest, uid):
            built.append(digest)
            return response

        with (
            patch("app.services.user_service.UserService") as mock_user_svc_cls,
            patch.object(
                service, "_get_existing_digest", side_effect=fake_get_existing
            ),
            patch.object(
                service,
                "_get_user_digest_format",
                new_callable=AsyncMock,
                return_value="editorial",
            ),
            patch.object(service, "_build_digest_response", side_effect=fake_build),
            patch("app.services.digest_service._schedule_background_regen"),
        ):
            mock_user_svc_cls.return_value.get_or_create_profile = AsyncMock()
            result = await service.get_or_create_digest(
                user_id=user_id, target_date=today, is_serene=True
            )

        assert result is response
        # flat_v1 was never passed to _build_digest_response.
        assert flat_yesterday not in built
        assert modern_two_days_ago in built
