"""Configuration de la base de données avec SQLAlchemy async."""

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from app.config import get_settings

settings = get_settings()

from sqlalchemy.pool import NullPool

# Engine async
# Diagnostic: Print engine target
import structlog
logger = structlog.get_logger()
logger.info("engine_initializing", target=settings.database_url.split('@')[-1] if settings.database_url else 'NONE')

engine = create_async_engine(
    settings.database_url,
    echo=settings.debug,
    # IMPORTANT: With psycopg, pool_pre_ping can be True, but since we are using
    # PgBouncer in transaction mode, we stay safe.
    pool_pre_ping=False,
    # Use NullPool with PgBouncer transaction pooling
    poolclass=NullPool,
    # Note: psycopg v3 doesn't support command_timeout in connect_args
    # Timeouts are handled at the statement level with statement_timeout if needed
    connect_args={
        "prepare_threshold": None,  # Disable prepared statements for PgBouncer transaction mode
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

