"""The weekly rescue job is registered on the scheduler (Story 12.2, T3-job)."""

from unittest.mock import Mock, patch

from apscheduler.triggers.cron import CronTrigger

from app.workers.scheduler import start_scheduler


def test_rescue_job_registered_weekly():
    with patch("app.workers.scheduler.AsyncIOScheduler") as mock_cls:
        mock_scheduler = Mock()
        mock_cls.return_value = mock_scheduler
        captured: dict = {}

        def capture(*args, **kwargs):
            jid = kwargs.get("id")
            if jid:
                entry = dict(kwargs)
                entry["func"] = args[0] if args else kwargs.get("func")
                captured[jid] = entry

        mock_scheduler.add_job = capture
        start_scheduler()

    assert "rescue_failed_sources" in captured
    job = captured["rescue_failed_sources"]
    assert job["func"].__name__ == "run_rescue_failed_sources"
    trigger = job["trigger"]
    assert isinstance(trigger, CronTrigger)
    fields = {f.name: str(f) for f in trigger.fields}
    assert fields["day_of_week"] == "mon"
    assert fields["hour"] == "4"
    assert fields["minute"] == "30"
