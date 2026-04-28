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

_PARIS_TZ = pytz.timezone("Europe/Paris")

scheduler: AsyncIOScheduler | None = None


async def _digest_watchdog() -> None:
    """Watchdog 7h30 : vérifie la couverture digest et relance si nécessaire.

    Counts `(user_id, is_serene)` pairs so a user is only considered
    "covered" when BOTH the normal and serein variants exist. Previously
    the watchdog counted distinct `user_id`s, which meant a user missing
    only the serein variant was never retried and flipped to silent
    fallback forever.

    If coverage < 90 %, relance `run_digest_generation()` qui skip les
    users already fully covered.
    """
    from sqlalchemy import func, select

    from app.database import safe_async_session
    from app.models.daily_digest import DailyDigest
    from app.models.user import UserProfile
    from app.utils.time import today_paris

    try:
        async with safe_async_session() as session:
            try:
                today = today_paris()

                total_users = await session.scalar(
                    select(func.count()).select_from(UserProfile)
                )
                if not total_users:
                    logger.info("digest_watchdog_no_users")
                    return

                # Expected coverage = 2 digests per user (normal + serein).
                # Count distinct (user_id, is_serene) pairs via a GROUP BY
                # subquery rather than string-concat casts — clearer intent,
                # no implicit bool→text coercion, portable across backends.
                expected_pairs = total_users * 2
                pair_subq = (
                    select(DailyDigest.user_id, DailyDigest.is_serene)
                    .where(DailyDigest.target_date == today)
                    .group_by(DailyDigest.user_id, DailyDigest.is_serene)
                    .subquery()
                )
                pair_count = (
                    await session.scalar(select(func.count()).select_from(pair_subq))
                    or 0
                )

                coverage = pair_count / expected_pairs if expected_pairs else 0
                logger.info(
                    "digest_watchdog_check",
                    target_date=str(today),
                    total_users=total_users,
                    expected_pairs=expected_pairs,
                    pair_count=pair_count,
                    coverage_pct=round(coverage * 100, 1),
                )

                if coverage < 0.90:
                    logger.warning(
                        "digest_watchdog_low_coverage_triggering_generation",
                        coverage_pct=round(coverage * 100, 1),
                        missing=expected_pairs - pair_count,
                    )
                    await run_digest_generation(target_date=today)
                    logger.info("digest_watchdog_generation_completed")
                else:
                    logger.info("digest_watchdog_coverage_ok")
            finally:
                try:
                    await session.rollback()
                except Exception:
                    logger.warning(
                        "digest_watchdog outer rollback failed", exc_info=True
                    )

    except Exception:
        logger.exception("digest_watchdog_failed")


async def _zombie_session_sweeper() -> None:
    """Defensive belt : kill les sessions Supavisor `idle in transaction` > 5 min.

    Hot fix incident 2026-04-28. Le timeout Postgres
    `idle_in_transaction_session_timeout=60000ms` (cf. database.py
    connect_args) devrait déjà couvrir, mais ce sweeper sert de
    monitoring + filet de secours si une connexion contourne le SET
    (ex: pooler config drift, connexion ouverte avant un hot reload).

    Log :
    - `zombie_session_sweeper_clean` (debug) : aucun zombie détecté.
    - `zombie_session_sweeper_killed` (warning) : zombies tués →
      investigate, c'est qu'un `safe_async_session` est manqué quelque part.
    """
    from sqlalchemy import text

    from app.database import safe_async_session

    try:
        async with safe_async_session() as session:
            result = await session.execute(
                text(
                    """
                    SELECT
                        pg_terminate_backend(pid) AS terminated,
                        pid,
                        EXTRACT(EPOCH FROM (now() - state_change))::int AS idle_seconds
                    FROM pg_stat_activity
                    WHERE state = 'idle in transaction'
                      AND application_name = 'Supavisor'
                      AND state_change < now() - interval '5 minutes'
                      AND pid <> pg_backend_pid()
                    """
                )
            )
            killed = result.fetchall()
            if killed:
                logger.warning(
                    "zombie_session_sweeper_killed",
                    count=len(killed),
                    pids=[r[1] for r in killed],
                    max_idle_s=max(r[2] for r in killed),
                )
            else:
                logger.debug("zombie_session_sweeper_clean")
    except Exception:
        logger.exception("zombie_session_sweeper_failed")


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
        trigger=CronTrigger(hour=8, minute=0, timezone=_PARIS_TZ),
        id="daily_top3",
        name="Daily Top 3 Briefing",
        replace_existing=True,
    )

    # Job Digest Quotidien (6h00 Paris — avancé de 8h pour pré-générer avant le réveil)
    # misfire_grace_time=14400 (4h): couvre les redémarrages Railway longs.
    # coalesce=True: pas de double exécution si plusieurs triggers rattrapés.
    scheduler.add_job(
        run_digest_generation,
        trigger=CronTrigger(hour=6, minute=0, timezone=_PARIS_TZ),
        id="daily_digest",
        name="Daily Digest Generation",
        replace_existing=True,
        misfire_grace_time=14400,
        coalesce=True,
    )

    # Watchdog 7h30 — vérifie la couverture et relance si < 90%
    scheduler.add_job(
        _digest_watchdog,
        trigger=CronTrigger(hour=7, minute=30, timezone=_PARIS_TZ),
        id="digest_watchdog",
        name="Digest Generation Watchdog",
        replace_existing=True,
        misfire_grace_time=14400,
        coalesce=True,
    )

    # Job Storage Cleanup Quotidien (3h00 Paris - heure creuse)
    scheduler.add_job(
        cleanup_old_articles,
        trigger=CronTrigger(hour=3, minute=0, timezone=_PARIS_TZ),
        id="storage_cleanup",
        name="Storage Cleanup",
        replace_existing=True,
    )

    # Zombie session sweeper — kill Supavisor sessions stuck in
    # `idle in transaction` > 5 min (filet de sécurité par-dessus le
    # timeout Postgres + le rollback() en finally de safe_async_session).
    scheduler.add_job(
        _zombie_session_sweeper,
        trigger=IntervalTrigger(minutes=5),
        id="zombie_session_sweeper",
        name="Zombie session sweeper (idle in tx > 5min)",
        replace_existing=True,
    )

    scheduler.start()
    logger.info(
        "Scheduler started",
        jobs=[
            "rss_sync",
            "daily_top3",
            "daily_digest",
            "digest_watchdog",
            "storage_cleanup",
            "zombie_session_sweeper",
        ],
        rss_interval_minutes=settings.rss_sync_interval_minutes,
        digest_cron="06:00 Europe/Paris",
        watchdog_cron="07:30 Europe/Paris",
        top3_cron="08:00 Europe/Paris",
        cleanup_cron="03:00 Europe/Paris",
    )


def stop_scheduler() -> None:
    """Arrête le scheduler."""
    global scheduler

    if scheduler:
        scheduler.shutdown()
        scheduler = None
        logger.info("Scheduler stopped")
