"""Scheduler pour les jobs background."""

import pytz
import structlog
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger
from apscheduler.triggers.interval import IntervalTrigger

from app.config import get_settings
from app.jobs.digest_generation_job import (
    compute_digest_coverage,
    run_digest_generation,
)
from app.jobs.purge_deleted_users import purge_deleted_users
from app.jobs.recompute_source_language import recompute_source_language
from app.services.observability.cost_budget import log_budget_projection
from app.workers.rss_sync import sync_all_sources
from app.workers.storage_cleanup import cleanup_old_articles

logger = structlog.get_logger()
settings = get_settings()

_PARIS_TZ = pytz.timezone("Europe/Paris")

# Hour/minute (Paris) at which the daily digest cron fires. Imported by the
# startup catchup in app/main.py so it never generates earlier than the
# scheduled cron — avoids midnight regenerations on late-evening Railway
# deploys (RSS not yet refreshed → poor digest content).
#
# Pourquoi 07:30 et pas 06:00 (bug-digest-evening-content) : à 06:00 Paris
# les Unes du matin (Le Monde ~06h30, Le Figaro ~07h, Libération ~07h) ne
# sont pas encore publiées. Le pool des 200 contents les plus récents
# (hours_lookback=48 → ORDER BY published_at DESC LIMIT 200) est alors
# saturé par l'édition de la veille au soir et les dépêches nocturnes,
# donc le digest "Essentiel" servait des articles datés ~22h. La courbe
# des `published_at` montre un saut de 215 → 509 articles/heure entre
# 5h et 6h Paris : firer le cron à 07:30 garantit que les Unes du matin
# sont déjà dans le pool candidat.
DIGEST_CRON_HOUR_PARIS = 7
DIGEST_CRON_MINUTE_PARIS = 30

scheduler: AsyncIOScheduler | None = None


async def _digest_watchdog() -> None:
    """Watchdog 8h15 : vérifie la couverture digest et relance si nécessaire.

    Counts `(user_id, is_serene)` pairs so a user is only considered
    "covered" when BOTH the normal and serein variants exist. Previously
    the watchdog counted distinct `user_id`s, which meant a user missing
    only the serein variant was never retried and flipped to silent
    fallback forever.

    If coverage < 90 %, relance `run_digest_generation()` qui skip les
    users already fully covered.
    """
    from app.database import safe_async_session
    from app.utils.time import today_paris

    try:
        async with safe_async_session() as session:
            try:
                today = today_paris()

                # Couverture = paires (user_id, is_serene) présentes sur les
                # total_users * 2 attendues. Calcul factorisé dans
                # `compute_digest_coverage` (source unique, partagée avec le
                # résumé de run du job digest).
                total_users, pair_count, coverage = await compute_digest_coverage(
                    session, today
                )
                if not total_users:
                    logger.info("digest_watchdog_no_users")
                    return

                expected_pairs = total_users * 2
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
            # Métrique always-on (enabler observabilité scaling) : rend
            # l'idle-in-transaction requêtable/visible à chaque passage, même à
            # 0, sans dépendre du log warning conditionnel ci-dessous.
            logger.info("db_idle_in_transaction_swept", count=len(killed))
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


async def _pool_health_probe() -> None:
    """Sonde active du pool DB toutes les 5 min (enabler observabilité scaling).

    `/api/health/pool` ne loggue `db_pool_pressure_high` que lorsqu'il est
    *appelé* (passif). Cette sonde lit le pool périodiquement pour rendre la
    pression visible dans structlog/Sentry sans dépendre d'un appel externe,
    en réutilisant la même introspection (`read_pool_stats`).
    """
    import sentry_sdk

    from app.database import engine
    from app.observability.pool_stats import read_pool_stats

    try:
        stats = read_pool_stats(engine)
        usage_pct = stats.get("usage_pct")
        threshold = settings.pool_alert_threshold_pct
        if usage_pct is not None and usage_pct >= threshold:
            logger.warning("db_pool_pressure_high", source="probe", **stats)
            sentry_sdk.capture_message(
                f"DB pool pressure high: {usage_pct}% (>= {threshold}%)",
                level="warning",
            )
        else:
            logger.info("db_pool_probe", **stats)
    except Exception:
        logger.exception("pool_health_probe_failed")


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

    # Job Digest Quotidien (07h30 Paris — voir DIGEST_CRON_HOUR_PARIS pour le
    # rationale : à 06h les Unes du matin ne sont pas encore publiées).
    # misfire_grace_time=14400 (4h): couvre les redémarrages Railway longs.
    # coalesce=True: pas de double exécution si plusieurs triggers rattrapés.
    scheduler.add_job(
        run_digest_generation,
        trigger=CronTrigger(
            hour=DIGEST_CRON_HOUR_PARIS,
            minute=DIGEST_CRON_MINUTE_PARIS,
            timezone=_PARIS_TZ,
        ),
        id="daily_digest",
        name="Daily Digest Generation",
        replace_existing=True,
        misfire_grace_time=14400,
        coalesce=True,
    )

    # Watchdog 08h15 — vérifie la couverture et relance si < 90%.
    # Doit tourner *après* le cron principal (07h30) pour avoir une chance
    # de constater la couverture réelle avant de relancer.
    scheduler.add_job(
        _digest_watchdog,
        trigger=CronTrigger(hour=8, minute=15, timezone=_PARIS_TZ),
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

    # Hard-delete soft-deleted user accounts older than 30 days (4h00 Paris,
    # heure creuse, après storage_cleanup). Cf. App Store 5.1.1(v) compliance.
    scheduler.add_job(
        purge_deleted_users,
        trigger=CronTrigger(hour=4, minute=0, timezone=_PARIS_TZ),
        id="purge_deleted_users",
        name="Purge soft-deleted users (>30d)",
        replace_existing=True,
    )

    # Recalcul `sources.language` à partir des Content des 30 derniers jours
    # (3h30 Paris, après storage_cleanup pour partir d'un pool nettoyé).
    scheduler.add_job(
        recompute_source_language,
        trigger=CronTrigger(hour=3, minute=30, timezone=_PARIS_TZ),
        id="recompute_source_language",
        name="Recompute Source.language (majoritaire 30j)",
        replace_existing=True,
    )

    # Projection budget coût API externes (évidence G3 scaling) : conso du mois
    # courant par provider/call_site + projection ×2.25 (89→200 users), loguée
    # une fois par jour. Read-only, ne change aucun comportement.
    scheduler.add_job(
        log_budget_projection,
        trigger=CronTrigger(hour=5, minute=0, timezone=_PARIS_TZ),
        id="cost_budget_projection",
        name="Cost budget projection (api_usage_events)",
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

    # Sonde pool DB active (5 min) — rend la pression pool visible dans
    # structlog/Sentry sans dépendre d'un appel à /api/health/pool.
    scheduler.add_job(
        _pool_health_probe,
        trigger=IntervalTrigger(minutes=5),
        id="pool_health_probe",
        name="DB pool health probe (5min)",
        replace_existing=True,
    )

    scheduler.start()
    logger.info(
        "Scheduler started",
        jobs=[
            "rss_sync",
            "daily_digest",
            "digest_watchdog",
            "storage_cleanup",
            "purge_deleted_users",
            "recompute_source_language",
            "zombie_session_sweeper",
            "pool_health_probe",
        ],
        rss_interval_minutes=settings.rss_sync_interval_minutes,
        digest_cron="07:30 Europe/Paris",
        watchdog_cron="08:15 Europe/Paris",
        cleanup_cron="03:00 Europe/Paris",
    )


def stop_scheduler() -> None:
    """Arrête le scheduler."""
    global scheduler

    if scheduler:
        scheduler.shutdown()
        scheduler = None
        logger.info("Scheduler stopped")
