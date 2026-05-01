"""Tests pour le job de génération veille (Stories 18.1 + 18.2).

Pipeline Option C : `run_veille_generation_for_config` ouvre ses propres
sessions courtes via `session_maker`. Les tests injectent un fake maker
qui yield la `db_session` du fixture pour persister sur la base de test.
"""

from contextlib import asynccontextmanager
from datetime import UTC, date, datetime
from unittest.mock import AsyncMock, patch
from uuid import uuid4

import pytest
import pytest_asyncio
from sqlalchemy import select

from app.jobs.veille_generation_job import (
    run_veille_generation,
    run_veille_generation_for_config,
)
from app.models.user import UserProfile
from app.models.veille import (
    VeilleConfig,
    VeilleDelivery,
    VeilleFrequency,
    VeilleGenerationState,
    VeilleStatus,
)


@pytest_asyncio.fixture
async def test_user(db_session):
    user_id = uuid4()
    db_session.add(
        UserProfile(
            user_id=user_id,
            display_name="Job Test User",
            onboarding_completed=True,
        )
    )
    await db_session.commit()
    return user_id


@pytest_asyncio.fixture
async def active_config(db_session, test_user):
    """Config active dont next_scheduled_at est ≤ now (donc due)."""
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


class TestProcessConfig:
    async def test_creates_succeeded_delivery_with_empty_items(
        self, db_session, active_config, fake_session_maker
    ):
        target = date(2026, 5, 4)
        result = await run_veille_generation_for_config(
            active_config.id,
            target_date=target,
            session_maker=fake_session_maker,
        )

        assert result.veille_config_id == active_config.id
        assert result.target_date == target
        assert result.generation_state == VeilleGenerationState.SUCCEEDED
        assert result.items == []
        assert result.attempts == 1
        assert result.started_at is not None
        assert result.finished_at is not None
        assert result.generated_at is not None

    async def test_recomputes_next_scheduled_at(
        self, db_session, active_config, fake_session_maker
    ):
        prev_next = active_config.next_scheduled_at
        target = date(2026, 5, 4)
        await run_veille_generation_for_config(
            active_config.id,
            target_date=target,
            session_maker=fake_session_maker,
        )
        await db_session.refresh(active_config)

        assert active_config.last_delivered_at is not None
        assert active_config.next_scheduled_at != prev_next
        diff_days = (
            active_config.next_scheduled_at - active_config.last_delivered_at
        ).days
        assert diff_days >= 6

    async def test_idempotent_upsert(
        self, db_session, active_config, fake_session_maker
    ):
        """Rejouer (config_id, target_date) → 1 row, attempts incrémenté."""
        target = date(2026, 5, 4)

        first = await run_veille_generation_for_config(
            active_config.id,
            target_date=target,
            session_maker=fake_session_maker,
        )
        assert first.attempts == 1

        second = await run_veille_generation_for_config(
            active_config.id,
            target_date=target,
            session_maker=fake_session_maker,
        )

        assert second.id == first.id
        all_rows = (
            (
                await db_session.execute(
                    select(VeilleDelivery).where(
                        VeilleDelivery.veille_config_id == active_config.id,
                        VeilleDelivery.target_date == target,
                    )
                )
            )
            .scalars()
            .all()
        )
        assert len(list(all_rows)) == 1
        assert second.attempts == 2

    async def test_raises_when_config_missing(self, db_session, fake_session_maker):
        with pytest.raises(ValueError, match="introuvable"):
            await run_veille_generation_for_config(
                uuid4(),
                target_date=date(2026, 5, 4),
                session_maker=fake_session_maker,
            )

    async def test_persists_items_from_builder(
        self, db_session, active_config, fake_session_maker
    ):
        """Avec un builder qui retourne des items → ils sont persistés."""
        items = [
            {
                "cluster_id": "abc-123",
                "title": "Sujet test",
                "articles": [],
                "why_it_matters": "Important.",
            }
        ]
        builder = AsyncMock()
        builder.build = AsyncMock(return_value=items)

        result = await run_veille_generation_for_config(
            active_config.id,
            target_date=date(2026, 5, 4),
            session_maker=fake_session_maker,
            builder=builder,
        )

        assert result.items == items
        assert result.generation_state == VeilleGenerationState.SUCCEEDED
        builder.build.assert_awaited_once_with(active_config.id)


class TestRunVeilleGenerationScanner:
    async def test_no_due_configs_logs_and_returns(self, db_session):
        """Si aucune config n'est due → pas de delivery créée."""

        @asynccontextmanager
        async def _fake_session():
            yield db_session

        with patch("app.jobs.veille_generation_job.safe_async_session", _fake_session):
            await run_veille_generation(target_date=date(2026, 5, 4))
