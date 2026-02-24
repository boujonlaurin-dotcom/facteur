"""Point d'entrée de l'API Facteur."""

import logging
import os
import sys
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from typing import Any

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
    contents,
    digest,
    feed,
    internal,
    personalization,
    progress,
    sources,
    streaks,
    subscription,
    users,
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
                "lifespan_startup_failed_and_aborting", error=str(e), exc_info=True
            )
            # Capture to Sentry and flush BEFORE sys.exit(1) — otherwise the event is lost
            sentry_sdk.capture_exception(e)
            sentry_sdk.flush(timeout=5)
            sys.exit(1)
    else:
        logger.warning(
            "lifespan_db_checks_skipped", reason="DATABASE_URL not set in environment"
        )
    logger.info("lifespan_starting_scheduler")
    start_scheduler()

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
app.include_router(app_update.router, prefix="/api/app", tags=["AppUpdate"])


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


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "app.main:app",
        host=settings.host,
        port=settings.port,
        reload=settings.debug,
    )
