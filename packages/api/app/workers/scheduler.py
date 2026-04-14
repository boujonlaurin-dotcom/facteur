"""Scheduler pour les jobs background."""

import os
import signal

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

    from app.database import async_session_maker
    from app.models.daily_digest import DailyDigest
    from app.models.user import UserProfile
    from app.utils.time import today_paris

    try:
        async with async_session_maker() as session:
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
                await session.scalar(select(func.count()).select_from(pair_subq)) or 0
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

    except Exception:
        logger.exception("digest_watchdog_failed")


async def _scheduled_restart() -> None:
    """Restart périodique pour purger la fuite de sessions SQLAlchemy.

    Cf. docs/bugs/bug-infinite-load-requests.md. Probe `pg_stat_activity`
    a révélé que des sessions SQLAlchemy restent "idle in transaction" avec
    des ages jusqu'à 2h — handlers cancellés par timeout dont le
    `session.close()` échoue silencieusement. Le pool (20 max) se remplit
    au fil des heures → `pool_timeout=30s` pour toute nouvelle requête →
    symptôme "tout charge à l'infini".

    Solution permanente (P1/P2) : scoper les sessions par unité de travail
    atomique, sortir les I/O externes des `with session:`. En attendant,
    un restart programmé toutes les ~8h vide le pool côté Python + force
    Postgres à libérer les transactions orphelines via la fermeture TCP.

    Horaires choisis (01h / 09h / 17h Paris) pour éviter les fenêtres des
    autres jobs planifiés (03h cleanup, 06h digest, 07h30 watchdog, 08h top3).
    SIGTERM permet à FastAPI/uvicorn de drainer les requêtes en cours avant
    shutdown ; Railway relance le container immédiatement.

    À retirer dès que le fix architectural (P1/P2 du bug doc) est déployé
    et validé pendant ≥ 48h sans retour à saturation du pool.
    """
    logger.warning(
        "scheduled_restart_initiated",
        reason="sqlalchemy_pool_leak_mitigation",
        pid=os.getpid(),
        hint="Remove once bug-infinite-load-requests P1/P2 fixes deployed.",
    )
    os.kill(os.getpid(), signal.SIGTERM)


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

    # Restart programmé (mitigation fuite pool SQLAlchemy).
    # 3 slots à 8h d'intervalle, placés loin des autres crons :
    #   01h00 (entre 22h et 03h cleanup)
    #   09h00 (après watchdog 07h30 et top3 08h00)
    #   17h00 (milieu d'après-midi, trafic bas)
    # misfire_grace_time=60 : si Railway est down au moment du trigger, on
    # ne retente pas au redémarrage (un startup fait déjà un pool frais).
    scheduler.add_job(
        _scheduled_restart,
        trigger=CronTrigger(hour="1,9,17", minute=0, timezone=_PARIS_TZ),
        id="scheduled_restart",
        name="Scheduled Restart (pool leak mitigation)",
        replace_existing=True,
        misfire_grace_time=60,
        coalesce=True,
    )

    scheduler.start()
    logger.info(
        "Scheduler started",
        rss_interval_minutes=settings.rss_sync_interval_minutes,
        digest_cron="06:00 Europe/Paris",
        watchdog_cron="07:30 Europe/Paris",
        scheduled_restart_cron="01:00, 09:00, 17:00 Europe/Paris",
    )


def stop_scheduler() -> None:
    """Arrête le scheduler."""
    global scheduler

    if scheduler:
        scheduler.shutdown()
        scheduler = None
        logger.info("Scheduler stopped")
