"""Point d'entrée de l'API Facteur."""

import structlog
from contextlib import asynccontextmanager
from typing import AsyncGenerator

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

import os
import sys

# DEBUG STARTUP
print("\n" + "="*50, flush=True)
print("🚀 BACKEND STARTING...", flush=True)
print(f"🌍 ENV_KEYS: {sorted(list(os.environ.keys()))}", flush=True)
print(f"📍 DATABASE_URL: {os.environ.get('DATABASE_URL', 'NOT_SET')[:20]}...", flush=True)
print("="*50 + "\n", flush=True)

from app.config import get_settings
from app.database import init_db, close_db
from app.routers import (
    auth,
    contents,
    feed,
    sources,
    streaks,
    subscription,
    users,
    webhooks,
    internal,
)
from app.workers.scheduler import start_scheduler, stop_scheduler

# Configuration
settings = get_settings()

@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator:
    """Gère le cycle de vie de l'application (startup/shutdown)."""
    # Startup
    await init_db()
    start_scheduler()
    yield
    # Shutdown
    stop_scheduler()
    await close_db()

# Application FastAPI
app = FastAPI(
    title=settings.app_name,
    version=settings.app_version,
    lifespan=lifespan,
    debug=settings.debug,
)

# Configuration CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
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
app.include_router(internal.router, prefix="/api/internal", tags=["Internal"])


@app.get("/api/health", tags=["Health"])
async def health_check() -> dict[str, str]:
    """Endpoint de health check."""
    return {"status": "ok", "version": settings.app_version}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "app.main:app",
        host=settings.host,
        port=settings.port,
        reload=settings.debug,
    )

