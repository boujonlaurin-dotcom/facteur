"""Test configuration and fixtures for API tests."""

from uuid import uuid4

import pytest
import pytest_asyncio
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

# Register all models with Base.metadata
import app.models  # noqa: F401
from app.config import get_settings
from app.database import Base
from app.models.enums import SourceType
from app.models.source import Source

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


@pytest.fixture(scope="session")
def create_tables():
    """Create all database tables from model definitions (once per session).

    Not autouse — only runs when a test depends on db_session.
    This prevents pure unit tests from requiring a database connection.
    """
    import asyncio

    async def _setup():
        async with test_engine.begin() as conn:
            await conn.run_sync(Base.metadata.drop_all)
            await conn.run_sync(Base.metadata.create_all)

    asyncio.run(_setup())
    yield


@pytest_asyncio.fixture
async def db_session(create_tables):
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
