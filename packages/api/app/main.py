"""Point d'entrée de l'API Facteur."""

import structlog
from contextlib import asynccontextmanager
from typing import AsyncGenerator, Any

from fastapi import FastAPI, Depends, Request
from fastapi.middleware.cors import CORSMiddleware

import os
import sys

import os
import sys

# DEBUG STARTUP
print("\n" + "!"*60, flush=True)
print("🚀 BACKEND STARTING...", flush=True)
db_url = os.environ.get('DATABASE_URL')
print(f"🌍 RAILWAY_ENV: {os.environ.get('RAILWAY_ENVIRONMENT_NAME', 'unknown')}", flush=True)
print(f"🔌 PORT: {os.environ.get('PORT', 'NOT_SET')}", flush=True)
print(f"📦 RAILWAY_SERVICE: {os.environ.get('RAILWAY_SERVICE_NAME', 'unknown')}", flush=True)
print(f"📌 COMMIT_SHA: {os.environ.get('RAILWAY_GIT_COMMIT_SHA', 'unknown')[:7]}", flush=True)
print(f"🔑 DATABASE_URL_PRESENT: {'YES' if db_url else 'NO'}", flush=True)
if db_url:
    print(f"📏 DATABASE_URL_LENGTH: {len(db_url)}", flush=True)
    # Masked host for safety: postgresql://***@host:port/...
    from urllib.parse import urlparse
    try:
        parsed = urlparse(db_url.replace("postgresql+asyncpg://", "http://")) # urlparse trick
        print(f"🎯 DATABASE_TARGET: {parsed.hostname}:{parsed.port}", flush=True)
    except:
        print(f"🎯 DATABASE_TARGET: PARSE_ERROR", flush=True)
print(f"🌍 ALL_KEYS: {sorted(list(os.environ.keys()))}", flush=True)
print("!"*60 + "\n", flush=True)

from app.config import get_settings
from app.database import init_db, close_db, get_db, text
from sqlalchemy.ext.asyncio import AsyncSession
from app.routers import (
    auth,
    contents,
    feed,
    sources,
    streaks,
    subscription,
    users,
    webhooks,
    analytics,
    internal,
)
import time


from app.workers.scheduler import start_scheduler, stop_scheduler

# Configuration
settings = get_settings()

@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator:
    """Gère le cycle de vie de l'application (startup/shutdown)."""
    # Startup
    print("⏳ Lifespan: Initializing DB...", flush=True)
    try:
        await init_db()
        print("⏳ Lifespan: DB initialized.", flush=True)
    except Exception as e:
        print(f"❌ Lifespan: DB initialization failed: {e}", flush=True)
        # On continue quand même pour ne pas empêcher le démarrage de l'app 
        # (ce qui permet d'avoir accès au healthcheck et docs même si DB down)
        
    print("⏳ Lifespan: Starting scheduler...", flush=True)
    start_scheduler()
    print("⏳ Lifespan: Startup complete.", flush=True)
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

# Simple request logger middleware (defined first, executed last)
@app.middleware("http")
async def log_requests(request: Request, call_next):
    start_time = time.time()
    path = request.url.path
    method = request.method
    print(f"📥 Incoming: {method} {path}", flush=True)
    try:
        response = await call_next(request)
        duration = time.time() - start_time
        print(f"📤 Outgoing: {method} {path} - {response.status_code} ({duration:.2f}s)", flush=True)
        return response
    except Exception as e:
        duration = time.time() - start_time
        print(f"💥 Error: {method} {path} - {str(e)} ({duration:.2f}s)", flush=True)
        raise e

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
app.include_router(contents.router, prefix="/api/contents", tags=["Contents"])
app.include_router(sources.router, prefix="/api/sources", tags=["Sources"])
app.include_router(subscription.router, prefix="/api/subscription", tags=["Subscription"])
app.include_router(streaks.router, prefix="/api/streaks", tags=["Streaks"])
app.include_router(webhooks.router, prefix="/api/webhooks", tags=["Webhooks"])
app.include_router(analytics.router, prefix="/api/analytics", tags=["Analytics"])
app.include_router(internal.router, prefix="/api/internal", tags=["Internal"])


@app.get("/api/health", tags=["Health"])
async def health_check(db: AsyncSession = Depends(get_db)) -> dict[str, Any]:
    """Endpoint de health check avec vérification DB."""
    try:
        await db.execute(text("SELECT 1"))
        db_status = "connected"
    except Exception as e:
        db_status = f"error: {str(e)}"
        
    return {
        "status": "ok", 
        "version": settings.app_version,
        "database": db_status,
        "environment": settings.environment
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "app.main:app",
        host=settings.host,
        port=settings.port,
        reload=settings.debug,
    )

