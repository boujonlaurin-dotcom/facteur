"""Point d'entrée de l'API Facteur."""

import structlog
from contextlib import asynccontextmanager
from typing import AsyncGenerator, Any

from fastapi import FastAPI, Depends, Request
from fastapi.middleware.cors import CORSMiddleware

import os
import sys


# DEBUG STARTUP
structlog.configure(
    processors=[
        structlog.contextvars.merge_contextvars,
        structlog.processors.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer()
    ],
    logger_factory=structlog.PrintLoggerFactory(),
)
logger = structlog.get_logger()

db_url = os.environ.get('DATABASE_URL')
logger.info("backend_starting", 
    railway_env=os.environ.get('RAILWAY_ENVIRONMENT_NAME', 'unknown'),
    port=os.environ.get('PORT', 'NOT_SET'),
    railway_service=os.environ.get('RAILWAY_SERVICE_NAME', 'unknown'),
    commit_sha=os.environ.get('RAILWAY_GIT_COMMIT_SHA', 'unknown')[:7],
    database_url_present=bool(db_url)
)

from app.config import get_settings
from app.database import init_db, close_db, get_db, text
from sqlalchemy.ext.asyncio import AsyncSession
from app.routers import (
    auth,
    contents,
    digest,
    feed,
    sources,
    streaks,
    subscription,
    users,
    webhooks,
    analytics,
    internal,
    progress,
    personalization,
)
import time


from app.workers.scheduler import start_scheduler, stop_scheduler

# Configuration
settings = get_settings()

@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator:
    """Gère le cycle de vie de l'application (startup/shutdown)."""
    # Startup
    logger.info("lifespan_initializing_db")
    try:
        await init_db()
        logger.info("lifespan_db_initialized")
        
        # 🛡️ STARTUP CHECK: DATABASE MIGRATIONS
        # Must crash if DB is not up to date to avoid silent failures
        if not settings.skip_startup_checks:
            from app.checks import check_migrations_up_to_date
            await check_migrations_up_to_date()
        else:
            logger.warning("lifespan_startup_checks_skipped", reason="skip_startup_checks=True")
        
    except Exception as e:
        logger.critical("lifespan_startup_failed_and_aborting", error=str(e), exc_info=True)
        # Any exception during DB init or migration check is critical and should prevent startup.
        sys.exit(1)
    logger.info("lifespan_starting_scheduler")
    start_scheduler()
    logger.info("lifespan_startup_complete")
    yield
    # Shutdown
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
app.include_router(subscription.router, prefix="/api/subscription", tags=["Subscription"])
app.include_router(streaks.router, prefix="/api/streaks", tags=["Streaks"])
app.include_router(webhooks.router, prefix="/api/webhooks", tags=["Webhooks"])
app.include_router(analytics.router, prefix="/api/analytics", tags=["Analytics"])
app.include_router(internal.router, prefix="/api/internal", tags=["Internal"])
app.include_router(progress.router, prefix="/api/progress", tags=["Progress"])
app.include_router(personalization.router, prefix="/api/users/personalization", tags=["Personalization"])
    
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    """Log all uncaught exceptions."""
    logger.error("uncaught_exception", 
                 path=request.url.path, 
                 method=request.method, 
                 error=str(exc),
                 exc_info=True)
    from fastapi.responses import JSONResponse
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal Server Error", "error_type": type(exc).__name__}
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
        "probe": "liveness"
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
                "probe": "readiness"
            }
        )
        
    return {
        "status": "ready", 
        "version": settings.app_version,
        "database": db_status,
        "environment": settings.environment,
        "probe": "readiness"
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "app.main:app",
        host=settings.host,
        port=settings.port,
        reload=settings.debug,
    )

