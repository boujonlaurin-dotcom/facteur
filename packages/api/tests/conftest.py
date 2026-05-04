"""Test configuration and fixtures for API tests."""

from contextlib import asynccontextmanager
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
from app.services.feed_cache import FEED_CACHE

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


@pytest.fixture(autouse=True)
def _reset_feed_cache():
    # The module-level FEED_CACHE singleton survives across tests; without
    # an explicit reset a test that populates it for `user_uuid=X` can
    # silently feed its cached payload to the next test that reuses the
    # same UUID (heisenbugs). Clearing before AND after also guards
    # against test-ordering flakes.
    FEED_CACHE.clear()
    FEED_CACHE.reset_stats()
    yield
    FEED_CACHE.clear()
    FEED_CACHE.reset_stats()


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
    """Test session isolated via a connection-level transaction + savepoints.

    session.commit() inside a test releases a savepoint (not a real COMMIT),
    so conn.rollback() at teardown restores the DB to a clean state regardless
    of how many commits the test or its fixtures called.
    """
    conn = await test_engine.connect()
    await conn.begin()
    session = AsyncSession(
        bind=conn,
        expire_on_commit=False,
        join_transaction_mode="create_savepoint",
    )
    try:
        yield session
    finally:
        await session.close()
        await conn.rollback()
        await conn.close()


@pytest.fixture
def fake_session_maker(db_session):
    """Yield la session de test à chaque ouverture.

    Pour les composants qui prennent un `session_maker` (factory de sessions
    courtes ad-hoc, type `safe_async_session`). Singleton de test : tous les
    `async with` retournent la même `db_session` pour persister sur la base
    de test. À utiliser pour tester le pattern Option C sans pool réel.
    """

    @asynccontextmanager
    async def _maker():
        yield db_session

    return _maker


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
