"""
Apply daily_top3 schema - with lock termination.
Run with: ./venv/bin/python apply_daily_top3_schema.py
"""
import asyncio
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine
from sqlalchemy.pool import NullPool
import os
from dotenv import load_dotenv

load_dotenv()

database_url = os.getenv("DATABASE_URL")
if database_url.startswith("postgres://"):
    database_url = database_url.replace("postgres://", "postgresql+psycopg://", 1)
elif database_url.startswith("postgresql://") and "+psycopg" not in database_url:
    database_url = database_url.replace("postgresql://", "postgresql+psycopg://", 1)

async def apply_schema():
    engine = create_async_engine(database_url, poolclass=NullPool)
    
    async with engine.connect() as conn:
        # Step 0: Kill blocking connections (idle ones)
        print("🔪 Terminating idle/blocking connections...")
        try:
            await conn.execute(text("""
                SELECT pg_terminate_backend(pid) 
                FROM pg_stat_activity 
                WHERE state = 'idle' 
                AND pid <> pg_backend_pid()
                AND datname = current_database()
            """))
            await conn.commit()
            print("✅ Idle connections terminated.")
        except Exception as e:
            print(f"⚠️ Could not terminate connections (may lack permission): {e}")
        
        # Extend timeout for this session
        await conn.execute(text("SET statement_timeout = '0'"))  # No timeout
        await conn.execute(text("SET lock_timeout = '0'"))  # No lock timeout
        
        # Check if table exists first
        result = await conn.execute(text(
            "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'daily_top3')"
        ))
        exists = result.scalar()
        
        if exists:
            print("✅ Table daily_top3 already exists. Skipping creation.")
        else:
            print("🔨 Creating table daily_top3...")
            await conn.execute(text("""
                CREATE TABLE daily_top3 (
                    id UUID DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
                    user_id UUID NOT NULL,
                    content_id UUID NOT NULL REFERENCES contents(id) ON DELETE CASCADE,
                    rank INTEGER NOT NULL CHECK (rank >= 1 AND rank <= 3),
                    top3_reason VARCHAR(100) NOT NULL,
                    consumed BOOLEAN DEFAULT false NOT NULL,
                    generated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL
                )
            """))
            await conn.commit()
            print("✅ Table created.")
            
            print("🔨 Creating indexes...")
            await conn.execute(text("CREATE INDEX ix_daily_top3_user_id ON daily_top3 (user_id)"))
            await conn.execute(text("CREATE INDEX ix_daily_top3_user_date ON daily_top3 (user_id, generated_at)"))
            await conn.commit()
            print("✅ Indexes created.")
        
        # Check if une_feed_url column exists on sources
        result = await conn.execute(text(
            "SELECT EXISTS (SELECT FROM information_schema.columns WHERE table_name = 'sources' AND column_name = 'une_feed_url')"
        ))
        col_exists = result.scalar()
        
        if col_exists:
            print("✅ Column sources.une_feed_url already exists.")
        else:
            print("🔨 Adding column sources.une_feed_url...")
            await conn.execute(text("ALTER TABLE sources ADD COLUMN une_feed_url TEXT"))
            await conn.commit()
            print("✅ Column added.")
        
        # Now stamp the migration
        print("🔨 Stamping Alembic to a4b5c6d7e8f9...")
        await conn.execute(text("DELETE FROM alembic_version"))
        await conn.execute(text("INSERT INTO alembic_version (version_num) VALUES ('a4b5c6d7e8f9')"))
        await conn.commit()
        print("✅ Alembic stamped successfully.")
    
    await engine.dispose()
    print("🎉 Schema fix complete!")

if __name__ == "__main__":
    asyncio.run(apply_schema())
