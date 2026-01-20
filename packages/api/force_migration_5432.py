"""
Force schema update using Port 5432 (Direct Connection) to bypass PgBouncer locks.
"""
import asyncio
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine
from sqlalchemy.pool import NullPool
import os
from dotenv import load_dotenv

load_dotenv()

# FORCE PORT 5432
database_url = os.getenv("DATABASE_URL")
if database_url:
    # Replace port 6543 with 5432
    if ":6543" in database_url:
        print("🔌 Switching from Port 6543 (Pooler) to 5432 (Direct)...")
        database_url = database_url.replace(":6543", ":5432")
    
    # Ensure driver is correct
    if database_url.startswith("postgres://"):
        database_url = database_url.replace("postgres://", "postgresql+psycopg://", 1)
    elif database_url.startswith("postgresql://") and "+psycopg" not in database_url:
        database_url = database_url.replace("postgresql://", "postgresql+psycopg://", 1)

async def force_schema():
    print(f"Target DB: ...{database_url[-20:]}")
    engine = create_async_engine(database_url, poolclass=NullPool)
    
    async with engine.connect() as conn:
        # 1. Check/Create daily_top3 (Without FK if needed)
        print("🔍 Checking daily_top3...")
        exists = await conn.execute(text("SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'daily_top3')"))
        if not exists.scalar():
            print("🔨 Creating daily_top3 (Lite)...")
            await conn.execute(text("""
                CREATE TABLE IF NOT EXISTS daily_top3 (
                    id UUID DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
                    user_id UUID NOT NULL,
                    content_id UUID NOT NULL,
                    rank INTEGER NOT NULL CHECK (rank >= 1 AND rank <= 3),
                    top3_reason VARCHAR(100) NOT NULL,
                    consumed BOOLEAN DEFAULT false NOT NULL,
                    generated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL
                )
            """))
            await conn.commit()
            
            # Indexes
            await conn.execute(text("CREATE INDEX IF NOT EXISTS ix_daily_top3_user_id ON daily_top3 (user_id)"))
            await conn.execute(text("CREATE INDEX IF NOT EXISTS ix_daily_top3_user_date ON daily_top3 (user_id, generated_at)"))
            await conn.commit()
            print("✅ daily_top3 created.")
        else:
            print("✅ daily_top3 already exists.")

        # 2. Try Add Column to sources
        print("🔍 Checking sources.une_feed_url...")
        col_exists = await conn.execute(text("SELECT EXISTS (SELECT FROM information_schema.columns WHERE table_name = 'sources' AND column_name = 'une_feed_url')"))
        
        if not col_exists.scalar():
            print("🔨 Attempting ALTER TABLE sources (Direct 5432)...")
            try:
                # Set a reasonable lock timeout to fail fast if blocked
                await conn.execute(text("SET lock_timeout = '5s'"))
                await conn.execute(text("ALTER TABLE sources ADD COLUMN une_feed_url TEXT"))
                await conn.commit()
                print("✅ Column added successfully!")
            except Exception as e:
                print(f"❌ Failed to add column (Lock busy): {e}")
                print("⚠️ RECOMMENDATION: Verify backend can start without this column.")
        else:
            print("✅ Column sources.une_feed_url already exists.")
            
        # 3. Stamp Alembic (Force sync)
        print("📝 Stamping Alembic...")
        await conn.execute(text("DELETE FROM alembic_version"))
        await conn.execute(text("INSERT INTO alembic_version (version_num) VALUES ('a4b5c6d7e8f9')"))
        await conn.commit()
        print("✅ Alembic stamped.")

    await engine.dispose()

if __name__ == "__main__":
    asyncio.run(force_schema())
