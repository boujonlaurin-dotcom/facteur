"""Point d'entrée de l'API Facteur."""

import asyncio
import logging
import os
import socket
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from typing import Any

# Ceinture + bretelles : un timeout socket par défaut empêche un appel synchrone
# (urllib via feedparser, trafilatura, libs tierces) de bloquer indéfiniment un
# thread de l'executor par défaut quand l'upstream stalle byte-par-byte.
# 30 s couvre largement les RSS/HTML lents tout en garantissant qu'aucun
# `run_in_executor(...)` ne reste vivant au-delà même si `asyncio.wait_for`
# cancel sa coroutine. Cf. docs/bugs/bug-infinite-load-requests.md (thread
# poisoning avéré sur trafilatura et landmine sur feedparser.parse(url)).
socket.setdefaulttimeout(30)

# Bornes du startup digest catchup. Cf. docs/bugs/bug-infinite-load-requests.md :
# sans timeout, une génération qui hang sur un upstream (Mistral, Google News,
# Supabase) monopolisait le pool DB et gelait l'API entière. 5 min est large
# pour un catchup normal (< 2 min typiquement) tout en garantissant qu'un run
# cassé ne reste pas actif indéfiniment.
_STARTUP_CATCHUP_TIMEOUT_S = 300.0
# Lock anti-double-exécution : Railway peut relancer l'app pendant qu'un
# catchup précédent tourne encore. Sans lock, chaque relance empilait un run
# supplémentaire, multipliant la pression sur le pool DB.
_STARTUP_CATCHUP_LOCK = asyncio.Lock()

import sentry_sdk
import structlog
from fastapi import Depends, FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from sentry_sdk.integrations.fastapi import FastApiIntegration
from sentry_sdk.integrations.logging import LoggingIntegration
from sentry_sdk.integrations.sqlalchemy import SqlalchemyIntegration
from sentry_sdk.integrations.starlette import StarletteIntegration

# Structlog configuration
structlog.configure(
    processors=[
        structlog.contextvars.merge_contextvars,
        structlog.processors.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer(),
    ],
    logger_factory=structlog.PrintLoggerFactory(),
)
logger = structlog.get_logger()

db_url = os.environ.get("DATABASE_URL")
logger.info(
    "backend_starting",
    railway_env=os.environ.get("RAILWAY_ENVIRONMENT_NAME", "unknown"),
    port=os.environ.get("PORT", "NOT_SET"),
    railway_service=os.environ.get("RAILWAY_SERVICE_NAME", "unknown"),
    commit_sha=os.environ.get("RAILWAY_GIT_COMMIT_SHA", "unknown")[:7],
    database_url_present=bool(db_url),
)


from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.database import close_db, get_db, init_db, text
from app.routers import (
    analytics,
    app_update,
    auth,
    collections,
    community,
    contents,
    custom_topics,
    digest,
    feed,
    internal,
    personalization,
    progress,
    sources,
    streaks,
    subscription,
    users,
    waitlist,
    webhooks,
)
from app.workers.scheduler import start_scheduler, stop_scheduler

# Configuration
settings = get_settings()


def _get_alembic_head() -> str:
    """Retourne la révision Alembic HEAD depuis le code (ou 'unknown')."""
    try:
        from alembic.config import Config

        from alembic import script

        alembic_ini = os.path.join(
            os.path.dirname(os.path.abspath(__file__)), "..", "alembic.ini"
        )
        cfg = Config(alembic_ini)
        script_dir = script.ScriptDirectory.from_config(cfg)
        heads = script_dir.get_heads()
        return heads[0] if heads else "no-heads"
    except Exception:
        return "unknown"


# --- Sentry Initialization ---
if settings.sentry_dsn:
    sentry_sdk.init(
        dsn=settings.sentry_dsn,
        environment=settings.environment,
        release=os.environ.get("RAILWAY_GIT_COMMIT_SHA", "dev"),
        traces_sample_rate=0.1 if settings.is_production else 1.0,
        profiles_sample_rate=0.1 if settings.is_production else 0.0,
        integrations=[
            FastApiIntegration(transaction_style="endpoint"),
            StarletteIntegration(transaction_style="endpoint"),
            SqlalchemyIntegration(),
            LoggingIntegration(
                level=logging.INFO,
                event_level=logging.ERROR,
            ),
        ],
        send_default_pii=False,
    )
    sentry_sdk.set_tag("alembic_head", _get_alembic_head())
    sentry_sdk.set_tag(
        "railway_service", os.environ.get("RAILWAY_SERVICE_NAME", "unknown")
    )
    logger.info(
        "sentry_initialized",
        environment=settings.environment,
        release=os.environ.get("RAILWAY_GIT_COMMIT_SHA", "dev")[:7],
    )
else:
    logger.info("sentry_disabled", reason="SENTRY_DSN not set")


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator:
    """Gère le cycle de vie de l'application (startup/shutdown)."""
    # Startup
    # Only run DB checks when DATABASE_URL is explicitly provided (production/staging).
    # During Docker build or CI, no database is available and we must not crash.
    _has_explicit_db = bool(os.environ.get("DATABASE_URL"))
    logger.info("lifespan_initializing_db", has_explicit_db=_has_explicit_db)
    if _has_explicit_db:
        try:
            await init_db()
            logger.info("lifespan_db_initialized")

            # 🛡️ STARTUP CHECK: DATABASE MIGRATIONS
            # Must crash if DB is not up to date to avoid silent failures
            if not settings.skip_startup_checks:
                from app.checks import check_migrations_up_to_date

                await check_migrations_up_to_date()
            else:
                logger.warning(
                    "lifespan_startup_checks_skipped", reason="skip_startup_checks=True"
                )

        except Exception as e:
            logger.critical(
                "lifespan_startup_db_error",
                error=str(e),
                exc_info=True,
                hint="App will start in degraded mode. /api/health/ready will return 503.",
            )
            # Capture to Sentry but do NOT sys.exit(1) — crash loops are worse
            # than degraded mode. The readiness probe (/api/health/ready) will
            # correctly return 503, and pool_pre_ping will reconnect when DB is back.
            sentry_sdk.capture_exception(e)
            sentry_sdk.flush(timeout=5)
    else:
        logger.warning(
            "lifespan_db_checks_skipped", reason="DATABASE_URL not set in environment"
        )
    logger.info("lifespan_starting_scheduler")
    start_scheduler()

    # Startup catch-up: vérifie la couverture digest (pas juste l'existence).
    # Si < 90 % des users actifs ont un digest, relance la génération.
    #
    # BUG FIX (bug-infinite-load-requests.md) — borne strictement la durée de ce
    # catchup (5 min max) et garantit qu'une seule exécution tourne à la fois via
    # un Lock module-level. Sans ça, un Railway qui redémarre plusieurs fois en
    # cascade (ex. healthcheck flaky) empilait des runs de `run_digest_generation`
    # qui monopolisaient le pool DB et faisaient apparaître toute l'API comme
    # "loadant à l'infini".
    if _has_explicit_db:

        async def _startup_digest_catchup() -> None:
            """Vérifie la couverture digest du jour et relance si insuffisante."""
            # Garde-fou anti-double-exécution : si un catchup précédent est
            # encore en cours (ex. Railway relance l'app pendant que le premier
            # run est toujours actif), on skip — un 2e catchup n'apportera rien
            # et double la pression sur le pool DB.
            if _STARTUP_CATCHUP_LOCK.locked():
                logger.info(
                    "digest_startup_catchup_skipped",
                    reason="already_running",
                )
                return

            async with _STARTUP_CATCHUP_LOCK:
                try:
                    from datetime import datetime
                    from zoneinfo import ZoneInfo

                    from sqlalchemy import func
                    from sqlalchemy import select as sa_select

                    from app.database import async_session_maker
                    from app.jobs.digest_generation_job import run_digest_generation
                    from app.models.daily_digest import DailyDigest
                    from app.models.user import UserProfile

                    await asyncio.sleep(60)

                    async with async_session_maker() as session:
                        today = datetime.now(ZoneInfo("Europe/Paris")).date()

                        total_users = await session.scalar(
                            sa_select(func.count()).select_from(UserProfile)
                        )
                        if not total_users:
                            logger.info("digest_startup_catchup_no_users")
                            return

                        # Count (user_id, is_serene) pairs — aligned
                        # with the watchdog formula. A user is only
                        # "covered" when BOTH normal and serein exist.
                        expected_pairs = total_users * 2
                        pair_subq = (
                            sa_select(
                                DailyDigest.user_id, DailyDigest.is_serene
                            )
                            .where(DailyDigest.target_date == today)
                            .group_by(
                                DailyDigest.user_id, DailyDigest.is_serene
                            )
                            .subquery()
                        )
                        pair_count = (
                            await session.scalar(
                                sa_select(func.count()).select_from(pair_subq)
                            )
                            or 0
                        )

                        coverage = (
                            pair_count / expected_pairs
                            if expected_pairs
                            else 0
                        )
                        logger.info(
                            "digest_startup_catchup_check",
                            target_date=str(today),
                            total_users=total_users,
                            expected_pairs=expected_pairs,
                            pair_count=pair_count,
                            coverage_pct=round(coverage * 100, 1),
                        )

                        if coverage < 0.90:
                            logger.info(
                                "digest_startup_catchup_triggered",
                                target_date=str(today),
                                missing=expected_pairs - pair_count,
                            )
                            try:
                                await asyncio.wait_for(
                                    run_digest_generation(target_date=today),
                                    timeout=_STARTUP_CATCHUP_TIMEOUT_S,
                                )
                                logger.info("digest_startup_catchup_completed")
                            except TimeoutError:
                                logger.warning(
                                    "digest_startup_catchup_timeout",
                                    target_date=str(today),
                                    timeout_s=_STARTUP_CATCHUP_TIMEOUT_S,
                                    hint=(
                                        "Catchup aborted to protect DB pool. "
                                        "Scheduled runs will retry."
                                    ),
                                )
                        else:
                            logger.info(
                                "digest_startup_catchup_skipped",
                                reason="coverage_ok",
                                coverage_pct=round(coverage * 100, 1),
                            )
                except Exception:
                    logger.exception("digest_startup_catchup_failed")

        asyncio.create_task(_startup_digest_catchup())

    # Démarrage conditionnel du worker de classification ML
    ml_worker = None
    if settings.ml_enabled:
        from app.workers.classification_worker import get_worker

        ml_worker = get_worker()
        await ml_worker.start()
        logger.info("lifespan_ml_worker_started")
    else:
        logger.info("lifespan_ml_worker_skipped", reason="ML_ENABLED=false")

    logger.info("lifespan_startup_complete")
    yield
    # Shutdown
    if ml_worker:
        await ml_worker.stop()
        logger.info("lifespan_ml_worker_stopped")
    stop_scheduler()
    await close_db()


# Application FastAPI
# redirect_slashes=False prevents 307 redirects that break fetch API (used by Dio/Flutter Web)
app = FastAPI(
    title=settings.app_name,
    version=settings.app_version,
    lifespan=lifespan,
    debug=settings.debug,
    redirect_slashes=False,
)


# Configuration CORS - MUST be added AFTER the @middleware decorator to execute FIRST
# Note: allow_credentials=True is incompatible with allow_origins=["*"]
# For Flutter Web, we need to be permissive but also handle preflight correctly
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allow all origins for now (Flutter Web, production apps)
    allow_credentials=False,  # Must be False when using wildcard origins
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["*"],
)


# Budget max par requête HTTP — défense ultime contre "tout charge à l'infini".
# Cf. docs/bugs/bug-infinite-load-requests.md. Les PR #396/#397/#405 ont borné
# `/digest/both`, le startup catchup et la pipeline éditoriale. La round 2 a
# borné `/digest` et `/digest/generate` individuellement. Il manquait un
# filet global pour tous les autres endpoints (`/feed`, writes diverses) qui
# n'avaient toujours aucun timeout. Un seul endpoint qui hang sur un upstream
# (Mistral, Google News, Supabase) bloque sa connexion DB ; le pool (20 max)
# se remplit ; chaque nouvelle requête attend `pool_timeout` (30 s) → symptôme
# "tout l'API charge à l'infini" côté mobile, même si seule une minorité
# d'endpoints est réellement coincée.
#
# Cette middleware borne *chaque* requête à 60 s. Au-delà, la task est annulée
# (ce qui libère la session DB via le context manager de `get_db`) et on
# renvoie un 503 structuré que le client peut retry intelligemment. Les
# healthchecks et le /pool endpoint sont exemptés — ils doivent répondre
# instantanément même sous stress pour que l'on puisse diagnostiquer la panne.
_REQUEST_BUDGET_S = 60.0
_REQUEST_BUDGET_EXEMPT_PREFIXES = (
    "/api/health",  # liveness/readiness/pool — doivent rester observables
    "/docs",
    "/redoc",
    "/openapi.json",
)


@app.middleware("http")
async def request_timeout_middleware(request: Request, call_next: Any) -> Any:
    """Borne toute requête HTTP à `_REQUEST_BUDGET_S` secondes."""
    path = request.url.path
    if any(path.startswith(p) for p in _REQUEST_BUDGET_EXEMPT_PREFIXES):
        return await call_next(request)

    try:
        return await asyncio.wait_for(call_next(request), timeout=_REQUEST_BUDGET_S)
    except TimeoutError:
        # La task a été annulée → ses ressources (session DB, cursors) sont
        # relâchées via les context managers, ce qui protège le pool.
        logger.warning(
            "request_budget_exceeded",
            path=path,
            method=request.method,
            budget_s=_REQUEST_BUDGET_S,
            hint=(
                "Handler took longer than the global request budget. "
                "DB session released. Client should retry with backoff."
            ),
        )
        from fastapi.responses import JSONResponse

        return JSONResponse(
            status_code=503,
            content={
                "detail": "request_timeout",
                "budget_s": _REQUEST_BUDGET_S,
            },
        )


# Routes
app.include_router(auth.router, prefix="/api/auth", tags=["Auth"])
app.include_router(users.router, prefix="/api/users", tags=["Users"])
app.include_router(feed.router, prefix="/api/feed", tags=["Feed"])
app.include_router(digest.router, prefix="/api/digest", tags=["Digest"])
app.include_router(contents.router, prefix="/api/contents", tags=["Contents"])
app.include_router(sources.router, prefix="/api/sources", tags=["Sources"])
app.include_router(
    subscription.router, prefix="/api/subscription", tags=["Subscription"]
)
app.include_router(streaks.router, prefix="/api/streaks", tags=["Streaks"])
app.include_router(webhooks.router, prefix="/api/webhooks", tags=["Webhooks"])
app.include_router(analytics.router, prefix="/api/analytics", tags=["Analytics"])
app.include_router(internal.router, prefix="/api/internal", tags=["Internal"])
app.include_router(progress.router, prefix="/api/progress", tags=["Progress"])
app.include_router(
    personalization.router,
    prefix="/api/users/personalization",
    tags=["Personalization"],
)
app.include_router(collections.router, prefix="/api/collections", tags=["Collections"])
app.include_router(community.router, prefix="/api/community", tags=["Community"])
app.include_router(
    custom_topics.router,
    prefix="/api/personalization/topics",
    tags=["CustomTopics"],
)
app.include_router(app_update.router, prefix="/api/app", tags=["AppUpdate"])
app.include_router(waitlist.router, prefix="/api/waitlist", tags=["Waitlist"])


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    """Log all uncaught exceptions and forward to Sentry."""
    logger.error(
        "uncaught_exception",
        path=request.url.path,
        method=request.method,
        error=str(exc),
        exc_info=True,
    )
    # Sentry captures this automatically via FastApiIntegration,
    # but we set extra context for clarity
    with sentry_sdk.push_scope() as scope:
        scope.set_context(
            "request",
            {
                "path": request.url.path,
                "method": request.method,
                "query": str(request.query_params),
            },
        )
        sentry_sdk.capture_exception(exc)
    from fastapi.responses import JSONResponse

    return JSONResponse(
        status_code=500,
        content={"detail": "Internal Server Error", "error_type": type(exc).__name__},
    )


@app.get("/api/health", tags=["Health"])
async def health_check() -> dict[str, Any]:
    """
    Liveness probe - Railway uses this endpoint.

    Returns 200 OK as long as the app process is alive.
    Does NOT check database connectivity (to avoid startup deadlocks).

    For full readiness check including DB, use /api/health/ready.
    """
    return {
        "status": "ok",
        "version": settings.app_version,
        "environment": settings.environment,
        "probe": "liveness",
    }


@app.get("/api/health/ready", tags=["Health"])
async def readiness_check(db: AsyncSession = Depends(get_db)) -> dict[str, Any]:
    """
    Readiness probe - checks if app is ready to serve traffic.

    Verifies database connectivity. Use this for manual verification
    or for load balancers that need to know if the instance is ready.
    """
    try:
        await db.execute(text("SELECT 1"))
        db_status = "connected"
    except Exception as e:
        db_status = f"error: {str(e)}"
        # Return 503 if DB is not ready
        from fastapi.responses import JSONResponse

        return JSONResponse(
            status_code=503,
            content={
                "status": "not_ready",
                "version": settings.app_version,
                "database": db_status,
                "environment": settings.environment,
                "probe": "readiness",
            },
        )

    return {
        "status": "ready",
        "version": settings.app_version,
        "database": db_status,
        "environment": settings.environment,
        "probe": "readiness",
    }


@app.get("/api/health/pool", tags=["Health"])
async def pool_metrics() -> dict[str, Any]:
    """
    DB pool metrics — diagnostic for "requests loading indefinitely" incidents.

    Cf. docs/bugs/bug-infinite-load-requests.md. Quand le pool est saturé
    (`checkedout >= pool_size + max_overflow`), toutes les nouvelles requêtes
    attendent `pool_timeout` (30 s) avant de timeout → symptôme "tout charge
    à l'infini". Cet endpoint expose l'état du pool pour diagnostic immédiat.

    Unauth exprès : doit rester utilisable quand le reste de l'API est hors
    service. N'expose pas de données utilisateur, seulement des métriques
    agrégées.
    """
    from app.database import engine

    pool = engine.pool
    size = getattr(pool, "size", lambda: None)()
    checked_in = getattr(pool, "checkedin", lambda: None)()
    checked_out = getattr(pool, "checkedout", lambda: None)()
    overflow = getattr(pool, "overflow", lambda: None)()

    saturated = (
        checked_out is not None
        and size is not None
        and checked_out >= size + max(overflow or 0, 0)
    )

    metrics: dict[str, Any] = {
        "status": "saturated" if saturated else "ok",
        "pool_class": type(pool).__name__,
        "size": size,
        "checked_in": checked_in,
        "checked_out": checked_out,
        "overflow": overflow,
    }

    # Signal warning à Sentry dès que la saturation est proche (> 75 %). Permet
    # de corréler pics de latence et pool pressure sans avoir à déployer de
    # l'instrumentation supplémentaire.
    if checked_out is not None and size is not None and size > 0:
        usage_pct = checked_out / (size + max(overflow or 0, 0))
        metrics["usage_pct"] = round(usage_pct * 100, 1)
        if usage_pct >= 0.75:
            logger.warning(
                "db_pool_pressure_high",
                checked_out=checked_out,
                size=size,
                overflow=overflow,
                usage_pct=round(usage_pct * 100, 1),
            )

    return metrics


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "app.main:app",
        host=settings.host,
        port=settings.port,
        reload=settings.debug,
    )
