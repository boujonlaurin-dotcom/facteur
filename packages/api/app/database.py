"""Configuration de la base de données avec SQLAlchemy async."""

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase
from sqlalchemy.pool import NullPool, AsyncAdaptedQueuePool

from app.config import get_settings

settings = get_settings()

# Engine async
# Diagnostic: Print engine target
import structlog
logger = structlog.get_logger()
logger.info("engine_initializing", target=settings.database_url.split('@')[-1] if settings.database_url else 'NONE')

# Determine pool configuration based on environment
# Railway/Supabase: Use QueuePool with pre_ping for connection resilience
# Local dev: Can use NullPool for simplicity
_is_railway = "railway" in (settings.database_url or "").lower()
_is_supabase = "supabase" in (settings.database_url or "").lower()
_use_queue_pool = _is_railway or _is_supabase

if _use_queue_pool:
    # Railway/Supabase: Use AsyncAdaptedQueuePool for proper connection pooling
    # This handles connection drops better than NullPool
    logger.info("db_pool_config", pool_type="AsyncAdaptedQueuePool", pre_ping=True)
    engine = create_async_engine(
        settings.database_url,
        echo=settings.debug,
        # Enable pool_pre_ping to verify connections before use
        # This prevents "SSL connection has been closed unexpectedly" errors
        pool_pre_ping=True,
        # Use AsyncAdaptedQueuePool for proper connection management
        poolclass=AsyncAdaptedQueuePool,
        # Pool size optimized for Railway/Supabase
        pool_size=5,
        max_overflow=10,
        # Connection timeout - fail fast if pool exhausted
        pool_timeout=30,
        # Recycle connections after 1 hour to prevent stale connections
        pool_recycle=3600,
        # Connect args for PgBouncer compatibility
        connect_args={
            "prepare_threshold": None,  # Disable prepared statements for PgBouncer transaction mode
        },
    )
else:
    # Local development: Use NullPool for simplicity
    logger.info("db_pool_config", pool_type="NullPool", pre_ping=False)
    engine = create_async_engine(
        settings.database_url,
        echo=settings.debug,
        pool_pre_ping=False,
        poolclass=NullPool,
        connect_args={
            "prepare_threshold": None,
        },
    )



# Session factory
async_session_maker = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autocommit=False,
    autoflush=False,
)


class Base(DeclarativeBase):
    """Base class pour les modèles SQLAlchemy."""

    pass


import sys

async def init_db() -> None:
    """Initialise la connexion à la base de données."""
    # Log connection target (safely)
    target_url = engine.url.render_as_string(hide_password=True)
    logger.info("db_connection_check", target=target_url)
    
    # En production, les tables sont gérées via Supabase
    # Cette fonction vérifie juste que la connexion fonctionne
    try:
        import socket
        from urllib.parse import urlparse
        
        # Diagnostic DNS préventif
        try:
            db_host = engine.url.host
            if db_host:
                socket.gethostbyname(db_host)
        except socket.gaierror:
            logger.error("dns_error", host=db_host, hint="Check your DATABASE_URL on Railway.")
        
        async with engine.begin() as conn:
            # Test connection
            await conn.execute(text("SELECT 1"))
        logger.info("db_connection_successful")
    except Exception as e:
        logger.error("db_connection_failed", error=str(e), target=target_url)
        raise


async def close_db() -> None:
    """Ferme la connexion à la base de données."""
    await engine.dispose()


async def get_db() -> AsyncSession:
    """Dependency pour obtenir une session de base de données."""
    async with async_session_maker() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()

