"""Tests pour le job de génération veille (Story 18.1).

Note : le job lui-même utilise `safe_async_session` qui ouvre ses propres
sessions ; on ne peut pas mocker ça facilement. On teste donc la sous-
fonction `run_veille_generation_for_config` qui prend une session en
paramètre, et un test d'intégration léger pour `run_veille_generation`
(sans connexion réelle au pool — on patche `safe_async_session`).
"""

from datetime import UTC, date, datetime
from unittest.mock import patch
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
        self, db_session, active_config
    ):
        target = date(2026, 5, 4)
        result = await run_veille_generation_for_config(
            db_session, active_config.id, target_date=target
        )
        await db_session.commit()

        assert result.veille_config_id == active_config.id
        assert result.target_date == target
        assert result.generation_state == VeilleGenerationState.SUCCEEDED
        assert result.items == []
        assert result.attempts == 1
        assert result.started_at is not None
        assert result.finished_at is not None
        assert result.generated_at is not None

    async def test_recomputes_next_scheduled_at(
        self, db_session, active_config
    ):
        prev_next = active_config.next_scheduled_at
        target = date(2026, 5, 4)
        await run_veille_generation_for_config(
            db_session, active_config.id, target_date=target
        )
        await db_session.commit()
        await db_session.refresh(active_config)

        assert active_config.last_delivered_at is not None
        assert active_config.next_scheduled_at != prev_next
        # weekly + lundi (dow=0) → +7 jours par rapport à last_delivered.
        diff_days = (
            active_config.next_scheduled_at - active_config.last_delivered_at
        ).days
        assert diff_days >= 6  # au moins une semaine d'écart

    async def test_idempotent_upsert(self, db_session, active_config):
        """Rejouer le même (config_id, target_date) → 1 seule row, attempts incrémenté."""
        target = date(2026, 5, 4)

        first = await run_veille_generation_for_config(
            db_session, active_config.id, target_date=target
        )
        await db_session.commit()
        assert first.attempts == 1

        second = await run_veille_generation_for_config(
            db_session, active_config.id, target_date=target
        )
        await db_session.commit()
        await db_session.refresh(second)

        # Même row.
        assert second.id == first.id

        # 1 seule row pour ce (config, date).
        all_rows = (
            await db_session.execute(
                select(VeilleDelivery).where(
                    VeilleDelivery.veille_config_id == active_config.id,
                    VeilleDelivery.target_date == target,
                )
            )
        ).scalars().all()
        assert len(list(all_rows)) == 1
        assert second.attempts == 2

    async def test_raises_when_config_missing(self, db_session):
        with pytest.raises(ValueError, match="introuvable"):
            await run_veille_generation_for_config(
                db_session, uuid4(), target_date=date(2026, 5, 4)
            )


class TestRunVeilleGenerationScanner:
    async def test_no_due_configs_logs_and_returns(self, db_session):
        """Si aucune config n'est due → pas de delivery créée."""
        # On patche `safe_async_session` pour qu'il yield notre db_session,
        # afin que le scanner SELECT s'exécute sur la fixture (pas sur le
        # vrai pool). Le scanner utilise ALSO `safe_async_session` dans le
        # bloc per-config — comme il n'y a pas de config due, ce bloc n'est
        # jamais atteint.
        from contextlib import asynccontextmanager

        @asynccontextmanager
        async def _fake_session():
            yield db_session

        with patch(
            "app.jobs.veille_generation_job.safe_async_session", _fake_session
        ):
            await run_veille_generation(target_date=date(2026, 5, 4))
        # Pas d'exception → OK.
