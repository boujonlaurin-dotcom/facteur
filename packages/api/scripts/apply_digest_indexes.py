#!/usr/bin/env python3
"""
Apply digest performance indexes one at a time (no transaction).
Use when SQL Editor times out and CONCURRENTLY is not an option.
Each CREATE INDEX runs in its own commit; 30s retry on timeout.
"""
import asyncio
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from dotenv import load_dotenv
load_dotenv()

from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine
from sqlalchemy.pool import NullPool

# Indexes to create (exact SQL from hand-off)
INDEX_SQL = [
    ("ix_contents_source_published", "CREATE INDEX ix_contents_source_published ON contents (source_id, published_at DESC);"),
    ("ix_contents_curated_published", "CREATE INDEX ix_contents_curated_published ON contents (published_at DESC, source_id);"),
    ("ix_user_content_status_exclusion", "CREATE INDEX ix_user_content_status_exclusion ON user_content_status (user_id, content_id, is_hidden, is_saved, status);"),
    ("ix_sources_theme", "CREATE INDEX ix_sources_theme ON sources (theme);"),
]
ALEMBIC_VERSION = "x8y9z0a1b2c3"


def get_db_url():
    url = os.environ.get("DATABASE_URL", "").strip()
    if not url:
        return None
    if url.startswith("postgres://"):
        url = url.replace("postgres://", "postgresql+asyncpg://", 1)
    elif url.startswith("postgresql://") and "+asyncpg" not in url:
        url = url.replace("postgresql://", "postgresql+asyncpg://", 1)
    return url


async def index_exists(conn, index_name: str) -> bool:
    r = await conn.execute(
        text("SELECT 1 FROM pg_indexes WHERE indexname = :name"),
        {"name": index_name},
    )
    return r.scalar() is not None


async def run_one(engine, name: str, sql: str, retry: bool = True) -> bool:
    for attempt in range(2):
        try:
            async with engine.connect() as conn:
                await conn.execute(text(sql))
                await conn.commit()
            return True
        except Exception as e:
            if not retry or attempt > 0:
                print(f"   ❌ {name}: {e}")
                return False
            print(f"   ⚠️ {name} failed, retrying in 30s: {e}")
            await asyncio.sleep(30)
    return False


async def main():
    db_url = get_db_url()
    if not db_url:
        print("❌ DATABASE_URL not set")
        sys.exit(1)

    # No prepare_threshold for asyncpg (used by create_async_engine with postgresql+asyncpg)
    engine = create_async_engine(db_url, poolclass=NullPool)

    try:
        for name, sql in INDEX_SQL:
            async with engine.connect() as conn:
                if await index_exists(conn, name):
                    print(f"⏭️  {name} already exists, skip")
                    continue
            print(f"🔨 Creating {name}...")
            ok = await run_one(engine, name, sql)
            if not ok:
                sys.exit(1)
            async with engine.connect() as conn:
                if await index_exists(conn, name):
                    print(f"   ✅ {name} created")
                else:
                    print(f"   ❌ {name} not found after create")
                    sys.exit(1)

        # Record migration
        async with engine.connect() as conn:
            await conn.execute(
                text("INSERT INTO alembic_version (version_num) VALUES (:v) ON CONFLICT (version_num) DO NOTHING"),
                {"v": ALEMBIC_VERSION},
            )
            await conn.commit()
        print(f"📌 alembic_version: {ALEMBIC_VERSION} recorded")

        # Final list
        async with engine.connect() as conn:
            r = await conn.execute(text("SELECT indexname FROM pg_indexes WHERE indexname LIKE 'ix_%' ORDER BY indexname"))
            rows = r.fetchall()
        print("📋 Indexes matching ix_%:")
        for (row,) in rows:
            print(f"   {row}")
    finally:
        await engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
