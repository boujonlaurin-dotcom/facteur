"""Tests for the background job scheduler.

This module verifies that scheduled jobs are properly configured
to trigger at the expected times with correct timezones.

Tests:
- Scheduler job configuration
- Daily digest job at 07:30 Europe/Paris
- Job trigger parameters
"""

from unittest.mock import AsyncMock, Mock, patch

import pytest
from apscheduler.triggers.cron import CronTrigger

from app.services.recommendation.scoring_config import ScoringWeights
from app.workers.scheduler import (
    DIGEST_CRON_HOUR_PARIS,
    DIGEST_CRON_MINUTE_PARIS,
    SUBTOPIC_DECAY_HOUR_PARIS,
    SUBTOPIC_DECAY_MINUTE_PARIS,
    _digest_watchdog,
    decay_user_entity_affinity,
    decay_user_subtopic_weights,
    decayed_subtopic_weight,
    start_scheduler,
    stop_scheduler,
)


class TestScheduler:
    """Tests for the background job scheduler configuration."""

    def test_scheduler_has_daily_digest_job(self):
        """TEST-01: Verify daily digest job is scheduled at 07:30 Paris time."""
        with patch("app.workers.scheduler.AsyncIOScheduler") as mock_scheduler_class:
            # Create a mock scheduler instance
            mock_scheduler = Mock()
            mock_scheduler_class.return_value = mock_scheduler

            # Track the add_job calls
            add_job_calls = []

            def capture_add_job(*args, **kwargs):
                add_job_calls.append(
                    {
                        "func": args[0] if args else kwargs.get("func"),
                        "trigger": kwargs.get("trigger"),
                        "id": kwargs.get("id"),
                        "name": kwargs.get("name"),
                        "replace_existing": kwargs.get("replace_existing"),
                    }
                )

            mock_scheduler.add_job = capture_add_job

            # Start the scheduler
            start_scheduler()

            # Verify the scheduler was started
            mock_scheduler.start.assert_called_once()

            # Find the daily_digest job
            digest_jobs = [
                call for call in add_job_calls if call.get("id") == "daily_digest"
            ]
            assert len(digest_jobs) == 1, (
                f"Expected 1 daily_digest job, found {len(digest_jobs)}"
            )

            job = digest_jobs[0]

            # Verify the trigger is a CronTrigger
            assert isinstance(job["trigger"], CronTrigger), (
                f"Expected CronTrigger, got {type(job['trigger'])}"
            )

            # Verify the job uses run_digest_generation function
            assert job["func"].__name__ == "run_digest_generation", (
                f"Expected run_digest_generation, got {job['func'].__name__}"
            )

            # Verify timezone is Europe/Paris
            trigger_tz = str(job["trigger"].timezone)
            assert (
                "Europe/Paris" in trigger_tz
                or "CET" in trigger_tz
                or "CEST" in trigger_tz
            ), f"Expected Europe/Paris timezone, got {trigger_tz}"

            # Verify job name
            assert job["name"] == "Daily Digest Generation", (
                f"Expected 'Daily Digest Generation', got {job['name']}"
            )

            # Verify replace_existing is True
            assert job["replace_existing"] is True, (
                f"Expected replace_existing=True, got {job['replace_existing']}"
            )

    def test_daily_digest_job_trigger_params(self):
        """TEST-01: Verify digest job triggers at exactly 07:30 daily."""
        with patch("app.workers.scheduler.AsyncIOScheduler") as mock_scheduler_class:
            mock_scheduler = Mock()
            mock_scheduler_class.return_value = mock_scheduler

            captured_jobs = {}

            def capture_add_job(*args, **kwargs):
                job_id = kwargs.get("id")
                if job_id:
                    captured_jobs[job_id] = kwargs

            mock_scheduler.add_job = capture_add_job

            start_scheduler()

            # Find the daily_digest job
            assert "daily_digest" in captured_jobs, (
                f"daily_digest job not found. Jobs: {list(captured_jobs.keys())}"
            )

            digest_job = captured_jobs["daily_digest"]
            trigger = digest_job["trigger"]

            # Verify it's a CronTrigger
            assert isinstance(trigger, CronTrigger), (
                f"Expected CronTrigger, got {type(trigger)}"
            )

            # CronTrigger fields: [year, month, day, week, day_of_week, hour, minute, second]
            # Verify hour=7, minute=30 — see DIGEST_CRON_HOUR_PARIS comment
            # for rationale (bug-digest-evening-content: Unes du matin pas
            # encore publiées avant ~07:00 Paris).
            assert str(trigger.fields[5]) == "7", (
                f"Expected hour=7, got {trigger.fields[5]}"
            )
            assert str(trigger.fields[6]) == "30", (
                f"Expected minute=30, got {trigger.fields[6]}"
            )

    def test_scheduler_includes_rss_sync_job(self):
        """Verify RSS sync job is scheduled."""
        with patch("app.workers.scheduler.AsyncIOScheduler") as mock_scheduler_class:
            mock_scheduler = Mock()
            mock_scheduler_class.return_value = mock_scheduler

            job_ids = []

            def capture_add_job(*args, **kwargs):
                job_ids.append(kwargs.get("id"))

            mock_scheduler.add_job = capture_add_job

            start_scheduler()

            # Verify rss_sync job exists
            assert "rss_sync" in job_ids, f"rss_sync job not found. Jobs: {job_ids}"

    def test_stop_scheduler_shuts_down(self):
        """Verify stop_scheduler properly shuts down the scheduler."""
        with patch("app.workers.scheduler.AsyncIOScheduler") as mock_scheduler_class:
            mock_scheduler = Mock()
            mock_scheduler_class.return_value = mock_scheduler

            # Start and then stop
            start_scheduler()
            stop_scheduler()

            # Verify shutdown was called
            mock_scheduler.shutdown.assert_called_once()


class TestDigestJobConfiguration:
    """Tests specifically for the digest generation job configuration."""

    def test_digest_job_timezone_europe_paris(self):
        """TEST-01: Verify digest job uses Europe/Paris timezone."""
        with patch("app.workers.scheduler.AsyncIOScheduler") as mock_scheduler_class:
            mock_scheduler = Mock()
            mock_scheduler_class.return_value = mock_scheduler

            captured_triggers = {}

            def capture_add_job(*args, **kwargs):
                job_id = kwargs.get("id")
                if job_id:
                    captured_triggers[job_id] = kwargs.get("trigger")

            mock_scheduler.add_job = capture_add_job

            start_scheduler()

            # Check the daily_digest trigger timezone
            digest_trigger = captured_triggers.get("daily_digest")
            assert digest_trigger is not None, "daily_digest trigger not found"

            # Verify timezone (compare by IANA name — apscheduler may return
            # either a pytz tz or a zoneinfo.ZoneInfo depending on version).
            assert str(digest_trigger.timezone) == "Europe/Paris", (
                f"Expected Europe/Paris timezone, got {digest_trigger.timezone}"
            )

    def test_digest_job_cron_expression(self):
        """TEST-01: Verify digest job cron expression is 30 7 * * * (07:30 daily)."""
        with patch("app.workers.scheduler.AsyncIOScheduler") as mock_scheduler_class:
            mock_scheduler = Mock()
            mock_scheduler_class.return_value = mock_scheduler

            captured_triggers = {}

            def capture_add_job(*args, **kwargs):
                job_id = kwargs.get("id")
                if job_id:
                    captured_triggers[job_id] = kwargs.get("trigger")

            mock_scheduler.add_job = capture_add_job

            start_scheduler()

            # Check the daily_digest trigger
            digest_trigger = captured_triggers.get("daily_digest")
            assert digest_trigger is not None, "daily_digest trigger not found"

            # CronTrigger fields: [year, month, day, week, day_of_week, hour, minute, second]
            # Verify hour=7 (index 5), minute=30 (index 6)
            assert str(digest_trigger.fields[5]) == "7", (
                f"Expected hour=7, got {digest_trigger.fields[5]}"
            )
            assert str(digest_trigger.fields[6]) == "30", (
                f"Expected minute=30, got {digest_trigger.fields[6]}"
            )

    def test_scheduler_includes_watchdog_job(self):
        """Verify digest watchdog job is scheduled at 08:15 Paris."""
        with patch("app.workers.scheduler.AsyncIOScheduler") as mock_scheduler_class:
            mock_scheduler = Mock()
            mock_scheduler_class.return_value = mock_scheduler

            captured_jobs = {}

            def capture_add_job(*args, **kwargs):
                job_id = kwargs.get("id")
                if job_id:
                    captured_jobs[job_id] = kwargs

            mock_scheduler.add_job = capture_add_job

            start_scheduler()

            assert "digest_watchdog" in captured_jobs, (
                f"digest_watchdog job not found. Jobs: {list(captured_jobs.keys())}"
            )

            trigger = captured_jobs["digest_watchdog"]["trigger"]
            assert isinstance(trigger, CronTrigger)
            # Watchdog doit tourner APRÈS le cron principal (07:30) — 08:15
            assert str(trigger.fields[5]) == "8", (
                f"Expected hour=8, got {trigger.fields[5]}"
            )
            assert str(trigger.fields[6]) == "15", (
                f"Expected minute=15, got {trigger.fields[6]}"
            )

    def test_scheduler_includes_subtopic_weight_decay_job(self):
        """Verify learned subtopic weights decay before the daily digest."""
        with patch("app.workers.scheduler.AsyncIOScheduler") as mock_scheduler_class:
            mock_scheduler = Mock()
            mock_scheduler_class.return_value = mock_scheduler

            captured_jobs = {}

            def capture_add_job(*args, **kwargs):
                job_id = kwargs.get("id")
                if job_id:
                    captured_jobs[job_id] = {
                        "func": args[0] if args else kwargs.get("func"),
                        "trigger": kwargs.get("trigger"),
                        "name": kwargs.get("name"),
                    }

            mock_scheduler.add_job = capture_add_job

            start_scheduler()

            assert "subtopic_weight_decay" in captured_jobs
            job = captured_jobs["subtopic_weight_decay"]
            assert job["func"].__name__ == "decay_user_subtopic_weights"
            assert job["name"] == "Subtopic Weight Decay"
            trigger = job["trigger"]
            assert isinstance(trigger, CronTrigger)
            assert str(trigger.fields[5]) == str(SUBTOPIC_DECAY_HOUR_PARIS)
            assert str(trigger.fields[6]) == str(SUBTOPIC_DECAY_MINUTE_PARIS)
            # Invariant métier : le decay doit tourner AVANT le digest (il nudge
            # les poids que le scoring du digest consomme). Garde-fou contre une
            # régression du décalage horaire (06h50 < 07h30, cf. PYTHON-5M : le
            # decall évite le chevauchement avec la fenêtre de pression pool).
            decay_minutes = SUBTOPIC_DECAY_HOUR_PARIS * 60 + SUBTOPIC_DECAY_MINUTE_PARIS
            digest_minutes = DIGEST_CRON_HOUR_PARIS * 60 + DIGEST_CRON_MINUTE_PARIS
            assert decay_minutes < digest_minutes

    def test_scheduler_includes_entity_affinity_decay_job(self):
        """PR2 — l'affinité entités décroît au même créneau, avant le digest."""
        with patch("app.workers.scheduler.AsyncIOScheduler") as mock_scheduler_class:
            mock_scheduler = Mock()
            mock_scheduler_class.return_value = mock_scheduler

            captured_jobs = {}

            def capture_add_job(*args, **kwargs):
                job_id = kwargs.get("id")
                if job_id:
                    captured_jobs[job_id] = {
                        "func": args[0] if args else kwargs.get("func"),
                        "trigger": kwargs.get("trigger"),
                        "name": kwargs.get("name"),
                    }

            mock_scheduler.add_job = capture_add_job

            start_scheduler()

            assert "entity_affinity_decay" in captured_jobs
            job = captured_jobs["entity_affinity_decay"]
            assert job["func"] is decay_user_entity_affinity
            assert job["name"] == "Entity Affinity Decay"
            trigger = job["trigger"]
            assert isinstance(trigger, CronTrigger)
            assert str(trigger.fields[5]) == str(SUBTOPIC_DECAY_HOUR_PARIS)
            assert str(trigger.fields[6]) == str(SUBTOPIC_DECAY_MINUTE_PARIS)
            decay_minutes = SUBTOPIC_DECAY_HOUR_PARIS * 60 + SUBTOPIC_DECAY_MINUTE_PARIS
            digest_minutes = DIGEST_CRON_HOUR_PARIS * 60 + DIGEST_CRON_MINUTE_PARIS
            assert decay_minutes < digest_minutes

    def test_scheduled_restart_job_is_not_registered(self):
        """Regression guard: `scheduled_restart` was a temporary SIGTERM-based
        mitigation for a SQLAlchemy pool leak. Railway's `restartPolicyType:
        ALWAYS` now handles process recycling. The job must NOT be re-added.
        """
        with patch("app.workers.scheduler.AsyncIOScheduler") as mock_scheduler_class:
            mock_scheduler = Mock()
            mock_scheduler_class.return_value = mock_scheduler

            job_ids = []

            def capture_add_job(*args, **kwargs):
                job_ids.append(kwargs.get("id"))

            mock_scheduler.add_job = capture_add_job

            start_scheduler()

            assert "scheduled_restart" not in job_ids, (
                f"scheduled_restart job should not be registered. Jobs: {job_ids}"
            )

    def test_veille_generation_jobs_are_not_registered(self):
        """Regression guard: la veille bascule vers un filtre temps-réel sur
        le feed (story 23.1). Les jobs `veille_generation` (scan */30 min) et
        `veille_stuck_cleanup` (sweeper FAILED) ne doivent plus être enregistrés.
        """
        with patch("app.workers.scheduler.AsyncIOScheduler") as mock_scheduler_class:
            mock_scheduler = Mock()
            mock_scheduler_class.return_value = mock_scheduler

            job_ids = []

            def capture_add_job(*args, **kwargs):
                job_ids.append(kwargs.get("id"))

            mock_scheduler.add_job = capture_add_job

            start_scheduler()

            assert "veille_generation" not in job_ids, (
                f"veille_generation job should not be registered. Jobs: {job_ids}"
            )
            assert "veille_stuck_cleanup" not in job_ids, (
                f"veille_stuck_cleanup job should not be registered. Jobs: {job_ids}"
            )


class TestSubtopicWeightDecay:
    """Daily subtopic decay should move learned weights toward neutral 1.0."""

    def test_decayed_subtopic_weight_moves_toward_neutral(self):
        assert decayed_subtopic_weight(3.0) == pytest.approx(
            1.0 + (3.0 - 1.0) * ScoringWeights.SUBTOPIC_DECAY
        )
        assert decayed_subtopic_weight(3.0) < 3.0
        assert decayed_subtopic_weight(0.1) == pytest.approx(
            1.0 + (0.1 - 1.0) * ScoringWeights.SUBTOPIC_DECAY
        )
        assert decayed_subtopic_weight(0.1) > 0.1
        assert decayed_subtopic_weight(1.0) == pytest.approx(1.0)

    @pytest.mark.asyncio
    async def test_decay_job_runs_one_bulk_update(self):
        from contextlib import asynccontextmanager

        mock_session = AsyncMock()
        mock_session.execute = AsyncMock(return_value=Mock(rowcount=42))
        mock_session.commit = AsyncMock()

        @asynccontextmanager
        async def fake_session_manager():
            yield mock_session

        with patch(
            "app.database.safe_async_session",
            side_effect=lambda: fake_session_manager(),
        ):
            await decay_user_subtopic_weights()

        mock_session.execute.assert_awaited_once()
        statement, params = mock_session.execute.await_args.args
        sql = str(statement)
        assert "UPDATE user_subtopics" in sql
        assert "SET weight = 1.0 + (weight - 1.0) * :decay" in sql
        assert params == {"decay": ScoringWeights.SUBTOPIC_DECAY}
        mock_session.commit.assert_awaited_once()


class TestDigestWatchdogCoverage:
    """Watchdog must count (user_id, is_serene) pairs, not distinct users.

    Before the fix, a user with only the normal variant generated would show
    as "fully covered" by the watchdog, so the missing serein variant was
    never retried.
    """

    @pytest.mark.asyncio
    async def test_watchdog_expects_two_pairs_per_user(self):
        """total_users * 2 is the expected pair count (normal + serein)."""
        from contextlib import asynccontextmanager

        # Fake session: 10 users, 15 pairs generated (= 75% coverage)
        mock_session = AsyncMock()
        mock_session.scalar = AsyncMock(side_effect=[10, 15])  # total, pairs

        @asynccontextmanager
        async def fake_sm():
            yield mock_session

        with (
            patch(
                "app.database.safe_async_session",
                side_effect=lambda: fake_sm(),
            ),
            patch(
                "app.workers.scheduler.run_digest_generation",
                new_callable=AsyncMock,
            ) as mock_run,
        ):
            await _digest_watchdog()

        # 15 / 20 = 75% < 90% → should trigger run_digest_generation
        mock_run.assert_awaited_once()

    @pytest.mark.asyncio
    async def test_watchdog_skips_generation_when_coverage_ok(self):
        """>= 90% pair coverage should NOT trigger a rerun."""
        from contextlib import asynccontextmanager

        mock_session = AsyncMock()
        # 10 users, 19 pairs = 95% coverage
        mock_session.scalar = AsyncMock(side_effect=[10, 19])

        @asynccontextmanager
        async def fake_sm():
            yield mock_session

        with (
            patch(
                "app.database.safe_async_session",
                side_effect=lambda: fake_sm(),
            ),
            patch(
                "app.workers.scheduler.run_digest_generation",
                new_callable=AsyncMock,
            ) as mock_run,
        ):
            await _digest_watchdog()

        mock_run.assert_not_awaited()

    @pytest.mark.asyncio
    async def test_watchdog_handles_zero_users(self):
        """No users = nothing to do, no crash on division-by-zero."""
        from contextlib import asynccontextmanager

        mock_session = AsyncMock()
        mock_session.scalar = AsyncMock(return_value=0)

        @asynccontextmanager
        async def fake_sm():
            yield mock_session

        with (
            patch(
                "app.database.safe_async_session",
                side_effect=lambda: fake_sm(),
            ),
            patch(
                "app.workers.scheduler.run_digest_generation",
                new_callable=AsyncMock,
            ) as mock_run,
        ):
            await _digest_watchdog()

        # No users → early return, no generation attempted.
        mock_run.assert_not_awaited()


def _capture_all_jobs() -> dict:
    """Run start_scheduler() with a mocked APScheduler and capture every
    add_job(**kwargs) keyed by job id."""
    captured: dict = {}

    def capture_add_job(*args, **kwargs):
        job_id = kwargs.get("id")
        if job_id:
            captured[job_id] = kwargs

    with patch("app.workers.scheduler.AsyncIOScheduler") as mock_scheduler_class:
        mock_scheduler = Mock()
        mock_scheduler_class.return_value = mock_scheduler
        mock_scheduler.add_job = capture_add_job
        start_scheduler()

    return captured


class TestJobSerialization:
    """S1-A: every recurring job must be serialized (max_instances=1 +
    coalesce=True) so a run that overruns its interval never spawns a
    concurrent second run competing for the shared DB pool (PYTHON-5M)."""

    def test_every_job_has_max_instances_one(self):
        captured = _capture_all_jobs()
        assert captured, "no jobs captured — start_scheduler registered nothing"
        for job_id, kwargs in captured.items():
            assert kwargs.get("max_instances") == 1, (
                f"job {job_id} must set max_instances=1, "
                f"got {kwargs.get('max_instances')!r}"
            )

    def test_every_job_has_coalesce_true(self):
        captured = _capture_all_jobs()
        for job_id, kwargs in captured.items():
            assert kwargs.get("coalesce") is True, (
                f"job {job_id} must set coalesce=True, got {kwargs.get('coalesce')!r}"
            )

    def test_expected_jobs_present(self):
        """Guard: the serialization tests are vacuous if no jobs registered.
        Pin the known recurring jobs so a future rename surfaces here."""
        captured = _capture_all_jobs()
        for job_id in (
            "rss_sync",
            "daily_digest",
            "subtopic_weight_decay",
            "digest_watchdog",
            "storage_cleanup",
            "purge_deleted_users",
            "recompute_source_language",
            "cost_budget_projection",
            "zombie_session_sweeper",
            "pool_health_probe",
            "daily_essentiel_push_dispatch",
        ):
            assert job_id in captured, f"{job_id} not registered"


class TestDigestWatchdogConcurrencyGuard:
    """S1-B call-site guard: the watchdog must NOT launch a 2nd digest when a
    generation is already running, even if coverage < 90 %."""

    @pytest.mark.asyncio
    async def test_watchdog_skips_when_generation_running(self):
        from contextlib import asynccontextmanager

        mock_session = AsyncMock()
        # 10 users, 15 pairs = 75 % < 90 % → would normally trigger a rerun.
        mock_session.scalar = AsyncMock(side_effect=[10, 15])

        @asynccontextmanager
        async def fake_sm():
            yield mock_session

        with (
            patch(
                "app.database.safe_async_session",
                side_effect=lambda: fake_sm(),
            ),
            patch(
                "app.services.generation_state.is_generation_running",
                return_value=True,
            ),
            patch(
                "app.workers.scheduler.run_digest_generation",
                new_callable=AsyncMock,
            ) as mock_run,
        ):
            await _digest_watchdog()

        # Already running → skip despite low coverage.
        mock_run.assert_not_awaited()

    @pytest.mark.asyncio
    async def test_watchdog_triggers_when_not_running_and_low_coverage(self):
        from contextlib import asynccontextmanager

        mock_session = AsyncMock()
        mock_session.scalar = AsyncMock(side_effect=[10, 15])  # 75 %

        @asynccontextmanager
        async def fake_sm():
            yield mock_session

        with (
            patch(
                "app.database.safe_async_session",
                side_effect=lambda: fake_sm(),
            ),
            patch(
                "app.services.generation_state.is_generation_running",
                return_value=False,
            ),
            patch(
                "app.workers.scheduler.run_digest_generation",
                new_callable=AsyncMock,
            ) as mock_run,
        ):
            await _digest_watchdog()

        mock_run.assert_awaited_once()
