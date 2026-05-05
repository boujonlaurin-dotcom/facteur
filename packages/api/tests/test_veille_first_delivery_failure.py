"""Tests T1 — politique de retry + persistance FAILED de `_run_first_delivery_with_retry`.

Vérifie qu'une exception transitoire dans `run_veille_generation_for_config`
n'aboutit plus à une row stuck en `running` : retry 1× T+60s puis UPDATE FAILED
+ sentry capture si la 2e tentative échoue aussi.
"""

from __future__ import annotations

from datetime import UTC, date, datetime
from unittest.mock import AsyncMock, patch
from uuid import uuid4

import pytest_asyncio

from app.models.user import UserProfile
from app.models.veille import (
    VeilleConfig,
    VeilleDelivery,
    VeilleFrequency,
    VeilleGenerationState,
    VeilleStatus,
)
from app.routers import veille as veille_module


@pytest_asyncio.fixture
async def test_user(db_session):
    user_id = uuid4()
    db_session.add(
        UserProfile(
            user_id=user_id,
            display_name="First Delivery Test",
            onboarding_completed=True,
        )
    )
    await db_session.commit()
    return user_id


@pytest_asyncio.fixture
async def active_config(db_session, test_user):
    cfg = VeilleConfig(
        id=uuid4(),
        user_id=test_user,
        theme_id="education",
        theme_label="Éducation",
        frequency=VeilleFrequency.WEEKLY,
        day_of_week=0,
        delivery_hour=7,
        timezone="Europe/Paris",
        status=VeilleStatus.ACTIVE,
        next_scheduled_at=datetime(2026, 5, 1, 0, 0, tzinfo=UTC),
    )
    db_session.add(cfg)
    await db_session.commit()
    await db_session.refresh(cfg)
    return cfg


@pytest_asyncio.fixture
async def pending_delivery(db_session, active_config):
    """Row PENDING comme créée par le handler `generate_first_delivery`."""
    delivery = VeilleDelivery(
        id=uuid4(),
        veille_config_id=active_config.id,
        target_date=date(2026, 5, 4),
        generation_state=VeilleGenerationState.PENDING.value,
    )
    db_session.add(delivery)
    await db_session.commit()
    await db_session.refresh(delivery)
    return delivery


class TestFirstDeliveryRetry:
    async def test_retries_once_then_marks_failed(
        self, db_session, fake_session_maker, active_config, pending_delivery
    ):
        """2 échecs consécutifs → row FAILED + last_error + finished_at + sentry."""
        call_count = {"n": 0}

        async def _raise(*_a, **_kw):
            call_count["n"] += 1
            raise RuntimeError(f"boom-{call_count['n']}")

        with (
            patch.object(
                veille_module,
                "run_veille_generation_for_config",
                side_effect=_raise,
            ),
            patch.object(veille_module, "safe_async_session", fake_session_maker),
            patch.object(veille_module.asyncio, "sleep", new=AsyncMock()) as sleep_mock,
            patch.object(veille_module.sentry_sdk, "capture_exception") as sentry_mock,
            patch.object(
                veille_module,
                "EditorialLLMClient",
                return_value=AsyncMock(close=AsyncMock()),
            ),
        ):
            await veille_module._run_first_delivery_with_retry(
                config_id=active_config.id,
                target_date=date(2026, 5, 4),
                delivery_id=pending_delivery.id,
            )

        assert call_count["n"] == 2, "doit retenter exactement 1 fois"
        sleep_mock.assert_awaited_once_with(
            veille_module._FIRST_DELIVERY_RETRY_DELAY_SECONDS
        )
        sentry_mock.assert_called_once()

        await db_session.refresh(pending_delivery)
        assert pending_delivery.generation_state == VeilleGenerationState.FAILED.value
        assert pending_delivery.last_error is not None
        assert "RuntimeError" in pending_delivery.last_error
        assert pending_delivery.finished_at is not None
        assert pending_delivery.attempts == 1  # +1 du PENDING (0) à 1

    async def test_retry_succeeds_no_failed_persisted(
        self, db_session, fake_session_maker, active_config, pending_delivery
    ):
        """1er échec puis 2e succès → pas de FAILED, row reste intacte côté retry handler."""
        call_count = {"n": 0}

        async def _raise_then_ok(*_a, **_kw):
            call_count["n"] += 1
            if call_count["n"] == 1:
                raise RuntimeError("transient")
            return None

        with (
            patch.object(
                veille_module,
                "run_veille_generation_for_config",
                side_effect=_raise_then_ok,
            ),
            patch.object(veille_module, "safe_async_session", fake_session_maker),
            patch.object(veille_module.asyncio, "sleep", new=AsyncMock()),
            patch.object(veille_module.sentry_sdk, "capture_exception") as sentry_mock,
            patch.object(
                veille_module,
                "EditorialLLMClient",
                return_value=AsyncMock(close=AsyncMock()),
            ),
        ):
            await veille_module._run_first_delivery_with_retry(
                config_id=active_config.id,
                target_date=date(2026, 5, 4),
                delivery_id=pending_delivery.id,
            )

        assert call_count["n"] == 2
        sentry_mock.assert_not_called()

        await db_session.refresh(pending_delivery)
        # Le handler retry ne touche pas la row si la 2e tentative passe — c'est
        # `run_veille_generation_for_config` (mocké ici) qui ferait la transition.
        assert pending_delivery.generation_state == VeilleGenerationState.PENDING.value
        assert pending_delivery.last_error is None


class TestScannerFailedPersistence:
    """T1 — symétrique côté scanner `_process_config_with_semaphore`."""

    async def test_scanner_marks_failed_on_exception(
        self, db_session, fake_session_maker, active_config
    ):
        from app.jobs import veille_generation_job as job_module

        # La row RUNNING qu'aurait créée _phase1_mark_running.
        running = VeilleDelivery(
            id=uuid4(),
            veille_config_id=active_config.id,
            target_date=date(2026, 5, 4),
            generation_state=VeilleGenerationState.RUNNING.value,
            started_at=datetime.now(UTC),
            attempts=1,
        )
        db_session.add(running)
        await db_session.commit()

        async def _raise(*_a, **_kw):
            raise RuntimeError("scanner-boom")

        import asyncio as _asyncio

        sem = _asyncio.Semaphore(1)
        with (
            patch.object(
                job_module,
                "run_veille_generation_for_config",
                side_effect=_raise,
            ),
            patch.object(job_module, "safe_async_session", fake_session_maker),
            patch.object(job_module.sentry_sdk, "capture_exception") as sentry_mock,
        ):
            ok = await job_module._process_config_with_semaphore(
                sem,
                active_config.id,
                date(2026, 5, 4),
                builder=AsyncMock(),
            )

        assert ok is False
        sentry_mock.assert_called_once()

        await db_session.refresh(running)
        assert running.generation_state == VeilleGenerationState.FAILED.value
        assert "RuntimeError" in (running.last_error or "")
        assert running.finished_at is not None
        assert running.attempts == 2
