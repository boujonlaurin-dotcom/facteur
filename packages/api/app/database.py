"""Configuration de la base de données avec SQLAlchemy async."""

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from app.config import get_settings

settings = get_settings()

# Engine async
engine = create_async_engine(
    settings.database_url,
    echo=settings.debug,
    pool_pre_ping=True,
    pool_size=5,
    max_overflow=10,
    connect_args={
        "prepared_statement_cache_size": 0,
        "statement_cache_size": 0,
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
    print(f"🔍 Database connection check: target={target_url}", flush=True)
    
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
            print(f"❌ DNS Error: Host '{db_host}' could not be resolved.", flush=True)
            print(f"💡 Hint: Check your DATABASE_URL on Railway. Ensure it's correctly formatted (e.g., aws-0-eu-west-1.pooler.supabase.com).", flush=True)
        
        async with engine.begin() as conn:
            # Test connection
            await conn.execute(text("SELECT 1"))
        print("✅ Database connection successful", flush=True)
    except Exception as e:
        print(f"❌ Database connection failed: {e}", flush=True)
        print(f"💡 Diagnostic context: target={target_url}", flush=True)
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

