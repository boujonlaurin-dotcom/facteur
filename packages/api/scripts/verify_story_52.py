"""
Diagnostic script to verify Story 5.2 backend implementation.
Tests that html_content and audio_url fields are present and populated.
"""
import asyncio
import os
from dotenv import load_dotenv

load_dotenv()

async def main():
    from sqlalchemy import text
    from sqlalchemy.ext.asyncio import create_async_engine
    
    database_url = os.getenv("DATABASE_URL")
    if not database_url:
        print("❌ DATABASE_URL not set")
        return
    
    # Convert postgresql:// to postgresql+psycopg:// for async support
    if database_url.startswith("postgresql://"):
        database_url = database_url.replace("postgresql://", "postgresql+psycopg://", 1)
    
    engine = create_async_engine(database_url)
    
    async with engine.connect() as conn:
        # Test 1: Check if columns exist
        print("=" * 60)
        print("🔍 TEST 1: Checking if new columns exist in contents table")
        print("=" * 60)
        
        result = await conn.execute(text("""
            SELECT column_name, data_type 
            FROM information_schema.columns 
            WHERE table_name = 'contents' 
            AND column_name IN ('html_content', 'audio_url')
        """))
        columns = result.fetchall()
        
        if len(columns) == 2:
            print("✅ Both columns exist:")
            for col in columns:
                print(f"   - {col[0]}: {col[1]}")
        else:
            print(f"❌ Expected 2 columns, found {len(columns)}")
            return
        
        # Test 2: Check content with html_content populated
        print("\n" + "=" * 60)
        print("🔍 TEST 2: Checking articles with html_content")
        print("=" * 60)
        
        result = await conn.execute(text("""
            SELECT COUNT(*) 
            FROM contents 
            WHERE html_content IS NOT NULL 
            AND LENGTH(html_content) > 100
        """))
        count = result.scalar()
        print(f"📊 Articles with html_content (>100 chars): {count}")
        
        if count > 0:
            print("✅ html_content is being populated")
            
            # Show a sample
            result = await conn.execute(text("""
                SELECT title, source_id, LENGTH(html_content) as html_length
                FROM contents 
                WHERE html_content IS NOT NULL 
                AND LENGTH(html_content) > 100
                ORDER BY published_at DESC
                LIMIT 3
            """))
            samples = result.fetchall()
            print("\n📝 Sample articles:")
            for s in samples:
                print(f"   - {s[0][:50]}... ({s[2]} chars)")
        else:
            print("⚠️  No articles with html_content yet - sync may not have run")
        
        # Test 3: Check podcasts with audio_url populated
        print("\n" + "=" * 60)
        print("🔍 TEST 3: Checking podcasts with audio_url")
        print("=" * 60)
        
        result = await conn.execute(text("""
            SELECT COUNT(*) 
            FROM contents 
            WHERE audio_url IS NOT NULL
        """))
        count = result.scalar()
        print(f"📊 Podcasts with audio_url: {count}")
        
        if count > 0:
            print("✅ audio_url is being populated")
            
            # Show a sample
            result = await conn.execute(text("""
                SELECT title, audio_url
                FROM contents 
                WHERE audio_url IS NOT NULL
                ORDER BY published_at DESC
                LIMIT 3
            """))
            samples = result.fetchall()
            print("\n🎧 Sample podcasts:")
            for s in samples:
                print(f"   - {s[0][:50]}...")
                print(f"     URL: {s[1][:80]}...")
        else:
            print("⚠️  No podcasts with audio_url yet - sync may not have run")
        
        # Test 4: Overall stats
        print("\n" + "=" * 60)
        print("📈 OVERALL STATS")
        print("=" * 60)
        
        result = await conn.execute(text("""
            SELECT 
                COUNT(*) as total,
                SUM(CASE WHEN html_content IS NOT NULL THEN 1 ELSE 0 END) as with_html,
                SUM(CASE WHEN audio_url IS NOT NULL THEN 1 ELSE 0 END) as with_audio
            FROM contents
        """))
        stats = result.fetchone()
        print(f"Total contents: {stats[0]}")
        print(f"With html_content: {stats[1]} ({100*stats[1]/stats[0]:.1f}%)" if stats[0] > 0 else "")
        print(f"With audio_url: {stats[2]} ({100*stats[2]/stats[0]:.1f}%)" if stats[0] > 0 else "")
        
    await engine.dispose()
    print("\n✅ Diagnostic complete!")

if __name__ == "__main__":
    asyncio.run(main())
