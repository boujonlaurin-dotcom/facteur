"""Scheduler pour les jobs background."""

import pytz
import structlog
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger
from apscheduler.triggers.interval import IntervalTrigger

from app.config import get_settings
from app.jobs.digest_generation_job import run_digest_generation
from app.workers.rss_sync import sync_all_sources
from app.workers.storage_cleanup import cleanup_old_articles
from app.workers.top3_job import generate_daily_top3_job

logger = structlog.get_logger()
settings = get_settings()

scheduler: AsyncIOScheduler | None = None


def start_scheduler() -> None:
    """Démarre le scheduler."""
    global scheduler

    scheduler = AsyncIOScheduler()

    # Job de synchronisation RSS (Intervalle)
    scheduler.add_job(
        sync_all_sources,
        trigger=IntervalTrigger(minutes=settings.rss_sync_interval_minutes),
        id="rss_sync",
        name="RSS Feed Synchronization",
        replace_existing=True,
    )

    # Job Top 3 Briefing Quotidien (8h00 Paris)
    scheduler.add_job(
        generate_daily_top3_job,
        trigger=CronTrigger(hour=8, minute=0, timezone=pytz.timezone("Europe/Paris")),
        id="daily_top3",
        name="Daily Top 3 Briefing",
        replace_existing=True,
    )

    # Job Digest Quotidien (8h00 Paris)
    scheduler.add_job(
        run_digest_generation,
        trigger=CronTrigger(hour=8, minute=0, timezone=pytz.timezone("Europe/Paris")),
        id="daily_digest",
        name="Daily Digest Generation",
        replace_existing=True,
    )

    # Job Storage Cleanup Quotidien (3h00 Paris - heure creuse)
    scheduler.add_job(
        cleanup_old_articles,
        trigger=CronTrigger(hour=3, minute=0, timezone=pytz.timezone("Europe/Paris")),
        id="storage_cleanup",
        name="Storage Cleanup",
        replace_existing=True,
    )

    scheduler.start()
    logger.info(
        "Scheduler started",
        rss_interval_minutes=settings.rss_sync_interval_minutes,
    )


def stop_scheduler() -> None:
    """Arrête le scheduler."""
    global scheduler

    if scheduler:
        scheduler.shutdown()
        scheduler = None
        logger.info("Scheduler stopped")
