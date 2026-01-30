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

settings = get_settings()

# Use the same database but with a test schema or separate tables
# For now, we'll use the main database but roll back transactions
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
