"""Test configuration and fixtures for API tests."""

import pytest
import pytest_asyncio
from uuid import uuid4

from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker
from sqlalchemy.pool import NullPool

from app.config import get_settings
from app.models.source import Source
from app.models.enums import SourceType
from app.database import Base

# Register all models with Base.metadata
import app.models  # noqa: F401

settings = get_settings()

test_engine = create_async_engine(
    settings.database_url,
    echo=False,
    pool_pre_ping=False,
    poolclass=NullPool,
    connect_args={
        "prepare_threshold": None,
    },
)

TestSessionLocal = async_sessionmaker(
    test_engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autocommit=False,
    autoflush=False,
)


@pytest.fixture(scope="session", autouse=True)
def create_tables():
    """Create all database tables from model definitions (once per session)."""
    import asyncio

    async def _setup():
        async with test_engine.begin() as conn:
            await conn.run_sync(Base.metadata.drop_all)
            await conn.run_sync(Base.metadata.create_all)

    asyncio.run(_setup())
    yield


@pytest_asyncio.fixture
async def db_session():
    """Create a test database session with automatic rollback."""
    async with TestSessionLocal() as session:
        try:
            yield session
        finally:
            await session.rollback()
            await session.close()


@pytest_asyncio.fixture
async def test_source(db_session):
    """Create a test source for content items."""
    source = Source(
        id=uuid4(),
        name="Test Source",
        url="https://example.com",
        feed_url=f"https://example.com/test-feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_active=True,
        is_curated=False,
    )
    db_session.add(source)
    await db_session.commit()
    return source
