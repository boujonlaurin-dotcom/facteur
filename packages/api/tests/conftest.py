"""Test configuration and fixtures for API tests."""

from contextlib import asynccontextmanager
from datetime import UTC
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
    # against test-ordering flakes. `clear()` also resets the invalidation
    # generations — a counter left high by one test would silently drop the
    # next test's `put()`.
    FEED_CACHE.clear()
    FEED_CACHE.reset_stats()
    yield
    FEED_CACHE.clear()
    FEED_CACHE.reset_stats()


@pytest.fixture
def feed_cache_payload():
    """Build a cached-feed payload mentioning the given content ids.

    `FeedPageCache.invalidate_content` matches by scanning the serialized
    payload for `str(content_id)`, so the shape of this string *is* the
    contract under test — hence one definition shared by the unit tests
    (`tests/services/test_feed_cache.py`) and the endpoint tests
    (`tests/routers/test_feed_cache_invalidation_sites.py`) rather than a
    copy in each. The real serialization is pinned separately by
    `test_cached_payload_item_ids_match_str_uuid`.
    """

    def _build(*content_ids) -> bytes:
        items = ", ".join(f'{{"id": "{cid}"}}' for cid in content_ids)
        return f'{{"items": [{items}]}}'.encode()

    return _build


@pytest.fixture
def feed_response_factory():
    """Build a minimal real `FeedResponse` (n items, one source).

    `FeedResponse` / `FeedItemResponse` are required-field-heavy, so one
    factory keeps the log tests and the serialization-invariant test from
    breaking apart when a field is added.
    """
    from datetime import datetime

    from app.models.enums import ContentType
    from app.schemas.content import SourceMini
    from app.schemas.feed import FeedItemResponse, FeedResponse, PaginationMeta

    def _build(*, items: int = 3, content_ids: list | None = None):
        ids = (
            content_ids if content_ids is not None else [uuid4() for _ in range(items)]
        )
        source = SourceMini(
            id=uuid4(), name="Test Source", logo_url=None, type="article", theme="tech"
        )
        return FeedResponse(
            items=[
                FeedItemResponse(
                    id=content_id,
                    title=f"Article {i}",
                    url=f"https://example.com/{i}",
                    thumbnail_url=None,
                    content_type=ContentType.ARTICLE,
                    duration_seconds=None,
                    published_at=datetime(2026, 6, 1, 12, 0, tzinfo=UTC),
                    source=source,
                )
                for i, content_id in enumerate(ids)
            ],
            pagination=PaginationMeta(
                page=1, per_page=12, total=len(ids), has_next=False
            ),
        )

    return _build


@pytest.fixture(autouse=True)
def _reset_mistral_rate_limiter():
    # The editorial Mistral rate limiter is a module-level singleton (LR-1
    # PR 1) bound to the running event loop. pytest-asyncio gives each test a
    # fresh loop, and the token bucket persists across tests — resetting it
    # gives every test a full bucket on its own loop, so the throttle never
    # injects real sleeps into unit tests (the limiter's own pacing is tested
    # directly with a fake clock in tests/editorial/test_rate_limiter.py).
    from app.services.editorial.llm_client import _reset_large_limiter

    _reset_large_limiter()
    yield
    _reset_large_limiter()


@pytest.fixture(scope="session")
def create_tables():
    """Create all database tables from model definitions (once per session).

    Not autouse — only runs when a test depends on db_session.
    This prevents pure unit tests from requiring a database connection.

    Story 22.1 — les types ENUM Postgres custom (ex: `interest_state`) sont
    créés en pré-requis via SQL brut, car les modèles SQLAlchemy les
    référencent avec `create_type=False` (la création passe par Alembic en
    prod). Sans cette étape, `Base.metadata.create_all` lèverait
    `psycopg.errors.UndefinedObject` au CREATE TABLE.
    """
    import asyncio

    from sqlalchemy import text

    async def _setup():
        async with test_engine.begin() as conn:
            # Use DROP SCHEMA CASCADE to cleanly wipe all tables (including
            # Alembic-only tables like article_feedback that are not in
            # Base.metadata), then recreate the schema. Without CASCADE,
            # Base.metadata.drop_all fails when unregistered tables have FK
            # constraints pointing to registered ones.
            await conn.execute(text("DROP SCHEMA public CASCADE"))
            await conn.execute(text("CREATE SCHEMA public"))
            await conn.execute(
                text(
                    "DO $$ BEGIN "
                    "CREATE TYPE interest_state AS ENUM "
                    "('hidden','unfollowed','followed','favorite'); "
                    "EXCEPTION WHEN duplicate_object THEN NULL; "
                    "END $$;"
                )
            )
            # pt01 — `Content` déclare un index d'expression trigram sur
            # `content_entities_text(entities)` (wrapper IMMUTABLE de
            # array_to_string, créé par Alembic en prod). Le DROP SCHEMA public
            # ci-dessus a effacé la fonction ; sans elle + l'opclass pg_trgm,
            # `Base.metadata.create_all` lèverait `UndefinedFunction` /
            # `UndefinedObject` au CREATE INDEX. Même logique que l'ENUM au-dessus.
            await conn.execute(text("CREATE SCHEMA IF NOT EXISTS extensions"))
            await conn.execute(
                text("CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA extensions")
            )
            await conn.execute(
                text(
                    "CREATE OR REPLACE FUNCTION public.content_entities_text(text[]) "
                    "RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE "
                    "AS $fn$ SELECT array_to_string($1, ' ') $fn$"
                )
            )
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
    async def _maker(**_kwargs):
        # Accepte (et ignore) les kwargs de cap (statement_timeout_ms,
        # idle_in_tx_timeout_ms) pour matcher la signature de
        # `safe_async_session` — cf. SessionMaker = Callable[..., ...].
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
