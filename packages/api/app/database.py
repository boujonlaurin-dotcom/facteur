"""Configuration de la base de données avec SQLAlchemy async."""

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase
from sqlalchemy.pool import AsyncAdaptedQueuePool, NullPool

from app.config import get_settings

settings = get_settings()

# Engine async
# Diagnostic: Print engine target with port info for troubleshooting
from urllib.parse import urlparse

import structlog

logger = structlog.get_logger()
_db_parsed = urlparse(settings.database_url) if settings.database_url else None
logger.info(
    "engine_initializing",
    host=_db_parsed.hostname if _db_parsed else "NONE",
    port=_db_parsed.port if _db_parsed else "NONE",
    database=_db_parsed.path.lstrip("/") if _db_parsed else "NONE",
    driver=settings.database_url.split("://")[0] if settings.database_url else "NONE",
)

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
        # Pool size optimized for Supabase PgBouncer (60 connection limit shared)
        # Conservative sizing to avoid overwhelming Supabase connection pooler
        pool_size=5,
        max_overflow=5,
        # Connection timeout - increased to prevent pool exhaustion
        pool_timeout=30,
        # Recycle connections frequently to prevent Supabase from killing them
        # Supabase PgBouncer idle timeout is ~5 minutes, recycle at 3 minutes
        pool_recycle=180,
        # Connect args for PgBouncer compatibility
        connect_args={
            "prepare_threshold": None,  # Disable prepared statements for PgBouncer transaction mode
            "connect_timeout": 10,  # Fail fast if DB host/port unreachable (prevents indefinite hang)
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


async def init_db() -> None:
    """Initialise la connexion à la base de données."""
    # Log connection target (safely) with port info
    target_url = engine.url.render_as_string(hide_password=True)
    db_host = engine.url.host
    db_port = engine.url.port
    logger.info("db_connection_check", target=target_url, host=db_host, port=db_port)

    # En production, les tables sont gérées via Supabase
    # Cette fonction vérifie juste que la connexion fonctionne
    try:
        import socket

        # Diagnostic DNS préventif
        try:
            if db_host:
                resolved_ip = socket.gethostbyname(db_host)
                logger.info("db_dns_resolved", host=db_host, ip=resolved_ip)
        except socket.gaierror:
            logger.error(
                "db_dns_error",
                host=db_host,
                port=db_port,
                hint="Check your DATABASE_URL on Railway.",
            )

        # Diagnostic TCP préventif — vérifier que le port est joignable
        try:
            if db_host and db_port:
                sock = socket.create_connection((db_host, db_port), timeout=5)
                sock.close()
                logger.info("db_tcp_reachable", host=db_host, port=db_port)
        except (TimeoutError, ConnectionRefusedError, OSError) as tcp_err:
            logger.error(
                "db_tcp_unreachable",
                host=db_host,
                port=db_port,
                error=str(tcp_err),
                hint="Port might be wrong. Supabase uses 6543 (transaction) or 5432 (session).",
            )

        async with engine.begin() as conn:
            # Test connection
            await conn.execute(text("SELECT 1"))
        logger.info("db_connection_successful", host=db_host, port=db_port)
    except Exception as e:
        logger.error(
            "db_connection_failed",
            error=str(e),
            host=db_host,
            port=db_port,
            target=target_url,
        )
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
