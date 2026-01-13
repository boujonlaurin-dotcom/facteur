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
    # Log connection target (safely)
    print(f"🔍 Database connection check: target={engine.url.host}:{engine.url.port}, db={engine.url.database}")
    
    # En production, les tables sont gérées via Supabase
    # Cette fonction vérifie juste que la connexion fonctionne
    try:
        async with engine.begin() as conn:
            # Test connection
            await conn.execute(text("SELECT 1"))
        print("✅ Database connection successful")
    except Exception as e:
        print(f"❌ Database connection failed: {e}")
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

