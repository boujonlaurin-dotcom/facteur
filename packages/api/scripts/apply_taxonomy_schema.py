#!/usr/bin/env python3
"""
Apply schema changes directly with extended statement timeout.
Run this if alembic migrations timeout on Supabase.
"""
import asyncio
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from sqlalchemy import text
from app.database import engine

async def apply_schema_changes():
    """Apply schema changes with extended timeout."""
    
    async with engine.connect() as conn:
        # Extend statement timeout to 5 minutes
        await conn.execute(text("SET statement_timeout = '300000'"))  # 5 min in ms
        
        print("Checking current migration state...")
        
        # Check alembic version
        result = await conn.execute(text("SELECT version_num FROM alembic_version"))
        current = result.fetchone()
        print(f"Current alembic version: {current[0] if current else 'None'}")
        
        # Check if constraint already exists
        result = await conn.execute(text("""
            SELECT constraint_name FROM information_schema.check_constraints
            WHERE constraint_name = 'ck_source_theme_valid'
        """))
        constraint_exists = result.fetchone() is not None
        
        # Check if topics column exists
        result = await conn.execute(text("""
            SELECT column_name FROM information_schema.columns
            WHERE table_name = 'contents' AND column_name = 'topics'
        """))
        topics_exists = result.fetchone() is not None
        
        # Check if user_subtopics table exists
        result = await conn.execute(text("""
            SELECT table_name FROM information_schema.tables
            WHERE table_name = 'user_subtopics'
        """))
        subtopics_exists = result.fetchone() is not None
        
        print(f"\n📊 Current state:")
        print(f"  - CHECK constraint ck_source_theme_valid: {'✓ exists' if constraint_exists else '✗ missing'}")
        print(f"  - Column contents.topics: {'✓ exists' if topics_exists else '✗ missing'}")
        print(f"  - Table user_subtopics: {'✓ exists' if subtopics_exists else '✗ missing'}")
        
        # Apply missing changes
        changes_made = False
        
        if not constraint_exists:
            print("\n🔄 Normalizing theme values and adding constraint...")
            await conn.execute(text("UPDATE sources SET theme = 'culture' WHERE theme = 'culture_ideas'"))
            await conn.execute(text("UPDATE sources SET theme = 'international' WHERE theme = 'geopolitics'"))
            await conn.execute(text("UPDATE sources SET theme = 'society' WHERE theme = 'society_climate'"))
            await conn.execute(text("""
                ALTER TABLE sources ADD CONSTRAINT ck_source_theme_valid 
                CHECK (theme IN ('tech', 'society', 'environment', 'economy', 'politics', 'culture', 'science', 'international'))
            """))
            print("  ✓ Constraint added")
            changes_made = True
        
        if not topics_exists:
            print("\n🔄 Adding topics column to contents (this may take a while)...")
            await conn.execute(text("ALTER TABLE contents ADD COLUMN topics TEXT[]"))
            print("  ✓ Column added")
            print("🔄 Creating GIN index...")
            await conn.execute(text("CREATE INDEX ix_contents_topics ON contents USING gin (topics)"))
            print("  ✓ Index created")
            changes_made = True
        
        if not subtopics_exists:
            print("\n🔄 Creating user_subtopics table...")
            await conn.execute(text("""
                CREATE TABLE user_subtopics (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    user_id UUID NOT NULL REFERENCES user_profiles(user_id) ON DELETE CASCADE,
                    topic_slug VARCHAR(50) NOT NULL,
                    weight FLOAT NOT NULL DEFAULT 1.0,
                    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
                    CONSTRAINT uq_user_subtopics_user_topic UNIQUE (user_id, topic_slug)
                )
            """))
            print("  ✓ Table created")
            changes_made = True
        
        # Update alembic version
        if changes_made:
            await conn.execute(text("DELETE FROM alembic_version"))
            await conn.execute(text("INSERT INTO alembic_version (version_num) VALUES ('k8l9m0n1o2p3')"))
            print("\n✓ Updated alembic version to k8l9m0n1o2p3")
        
        await conn.commit()
        
        print("\n✅ All schema changes applied successfully!")
        return True

if __name__ == "__main__":
    try:
        asyncio.run(apply_schema_changes())
    except Exception as e:
        print(f"\n❌ Error: {e}")
        sys.exit(1)
