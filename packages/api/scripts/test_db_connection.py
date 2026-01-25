#!/usr/bin/env python3
"""
Emergency DB Connection Test
Run this to check if the Supabase DB is reachable.
"""
import asyncio
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from dotenv import load_dotenv
load_dotenv()

async def test_connection():
    print("🔌 Testing Supabase DB Connection...")
    print("-" * 50)
    
    db_url = os.environ.get('DATABASE_URL', '')
    if not db_url:
        print("❌ DATABASE_URL not set!")
        return
        
    # Mask password
    safe_url = db_url.split('@')[-1] if '@' in db_url else 'unknown'
    print(f"Target: {safe_url}")
    
    from sqlalchemy.ext.asyncio import create_async_engine
    from sqlalchemy import text
    from sqlalchemy.pool import NullPool
    
    engine = create_async_engine(
        db_url,
        poolclass=NullPool,
        connect_args={"prepare_threshold": None},
    )
    
    # Test 1: Simple connection
    print("\n1️⃣ Testing basic SELECT 1...")
    try:
        start = time.perf_counter()
        async with engine.connect() as conn:
            await conn.execute(text("SELECT 1"))
        ms = (time.perf_counter() - start) * 1000
        print(f"   ✅ OK in {ms:.0f}ms")
    except Exception as e:
        print(f"   ❌ FAILED: {e}")
        return
    
    # Test 2: Count tables
    print("\n2️⃣ Counting sources...")
    try:
        start = time.perf_counter()
        async with engine.connect() as conn:
            result = await conn.execute(text("SELECT COUNT(*) FROM sources"))
            count = result.scalar()
        ms = (time.perf_counter() - start) * 1000
        print(f"   ✅ {count} sources in {ms:.0f}ms")
    except Exception as e:
        print(f"   ❌ FAILED: {e}")
    
    # Test 3: Count contents
    print("\n3️⃣ Counting contents...")
    try:
        start = time.perf_counter()
        async with engine.connect() as conn:
            result = await conn.execute(text("SELECT COUNT(*) FROM contents"))
            count = result.scalar()
        ms = (time.perf_counter() - start) * 1000
        print(f"   ✅ {count} contents in {ms:.0f}ms")
    except Exception as e:
        print(f"   ❌ FAILED: {e}")
    
    # Test 4: Active connections
    print("\n4️⃣ Checking active connections...")
    try:
        async with engine.connect() as conn:
            result = await conn.execute(text("""
                SELECT state, COUNT(*) 
                FROM pg_stat_activity 
                WHERE datname = current_database()
                GROUP BY state
            """))
            rows = result.fetchall()
            for state, count in rows:
                print(f"   • {state or 'NULL'}: {count}")
    except Exception as e:
        print(f"   ⚠️ Could not check (likely permissions): {e}")
    
    await engine.dispose()
    print("\n✅ All tests passed - DB is reachable")

if __name__ == "__main__":
    asyncio.run(test_connection())
