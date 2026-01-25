#!/usr/bin/env python3
"""
Diagnostic script for BREAKING filter issue.
Checks how many recent contents exist by source/theme.
"""
import asyncio
import os
import sys
from datetime import datetime, timedelta

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from dotenv import load_dotenv
load_dotenv()

async def debug_breaking():
    print("🔍 Debugging BREAKING filter...")
    print("=" * 60)
    
    from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
    from sqlalchemy.orm import sessionmaker
    from sqlalchemy import text, select, func
    from sqlalchemy.pool import NullPool
    
    db_url = os.environ.get('DATABASE_URL', '')
    engine = create_async_engine(db_url, poolclass=NullPool, connect_args={"prepare_threshold": None})
    
    async with engine.connect() as conn:
        # 1. Count curated sources by theme
        print("\n1️⃣ CURATED sources by theme (Hard News):")
        result = await conn.execute(text("""
            SELECT theme, COUNT(*) as count 
            FROM sources 
            WHERE is_curated = true 
              AND theme IN ('society', 'international', 'economy', 'politics')
            GROUP BY theme 
            ORDER BY count DESC
        """))
        for row in result:
            print(f"   {row[0]}: {row[1]} sources")
        
        # 2. Count contents from last 12h by source
        limit_date = datetime.utcnow() - timedelta(hours=12)
        print(f"\n2️⃣ Contents from last 12h (since {limit_date.isoformat()}):")
        result = await conn.execute(text("""
            SELECT s.name, s.theme, COUNT(c.id) as count
            FROM contents c
            JOIN sources s ON c.source_id = s.id
            WHERE s.is_curated = true
              AND c.published_at >= :limit_date
            GROUP BY s.name, s.theme
            ORDER BY count DESC
            LIMIT 20
        """), {"limit_date": limit_date})
        rows = result.fetchall()
        if not rows:
            print("   ❌ NO CONTENTS in last 12h!")
        for row in rows:
            theme_mark = "🔴" if row[1] in ('society', 'international', 'economy', 'politics') else "⚪"
            print(f"   {theme_mark} {row[0]} ({row[1]}): {row[2]} articles")
        
        # 3. Count contents from last 12h for Hard News themes only
        print(f"\n3️⃣ Hard News contents (last 12h):")
        result = await conn.execute(text("""
            SELECT s.name, s.theme, COUNT(c.id) as count
            FROM contents c
            JOIN sources s ON c.source_id = s.id
            WHERE s.is_curated = true
              AND s.theme IN ('society', 'international', 'economy', 'politics')
              AND c.published_at >= :limit_date
            GROUP BY s.name, s.theme
            ORDER BY count DESC
        """), {"limit_date": limit_date})
        rows = result.fetchall()
        total = 0
        for row in rows:
            print(f"   • {row[0]} ({row[1]}): {row[2]}")
            total += row[2]
        print(f"   TOTAL: {total} articles from Hard News themes")
        
        # 4. Check if any contents exist at all in these themes
        print(f"\n4️⃣ Most recent article per Hard News source:")
        result = await conn.execute(text("""
            SELECT s.name, s.theme, MAX(c.published_at) as latest
            FROM contents c
            JOIN sources s ON c.source_id = s.id
            WHERE s.is_curated = true
              AND s.theme IN ('society', 'international', 'economy', 'politics')
            GROUP BY s.name, s.theme
            ORDER BY latest DESC
            LIMIT 15
        """))
        for row in result:
            latest = row[2]
            age = datetime.utcnow() - latest if latest else None
            age_str = f"{age.total_seconds() / 3600:.1f}h ago" if age else "N/A"
            status = "✅" if age and age.total_seconds() < 12 * 3600 else "❌"
            print(f"   {status} {row[0]}: {age_str}")
        
        # 5. Check total contents per theme (all time)
        print(f"\n5️⃣ Total contents by theme (all time):")
        result = await conn.execute(text("""
            SELECT s.theme, COUNT(c.id) as count
            FROM contents c
            JOIN sources s ON c.source_id = s.id
            WHERE s.is_curated = true
            GROUP BY s.theme
            ORDER BY count DESC
        """))
        for row in result:
            mark = "🔴" if row[0] in ('society', 'international', 'economy', 'politics') else "⚪"
            print(f"   {mark} {row[0]}: {row[1]}")
        
        # 6. Check last sync time
        print(f"\n6️⃣ Last sync times for Hard News sources:")
        result = await conn.execute(text("""
            SELECT name, theme, last_synced_at
            FROM sources
            WHERE is_curated = true
              AND theme IN ('society', 'international', 'economy', 'politics')
            ORDER BY last_synced_at DESC NULLS LAST
            LIMIT 10
        """))
        for row in result:
            sync_time = row[2]
            if sync_time:
                age = datetime.utcnow() - sync_time.replace(tzinfo=None)
                age_str = f"{age.total_seconds() / 60:.0f}min ago"
            else:
                age_str = "NEVER SYNCED"
            print(f"   {row[0]}: {age_str}")
    
    await engine.dispose()
    print("\n" + "=" * 60)
    print("Diagnostic complete.")

if __name__ == "__main__":
    asyncio.run(debug_breaking())
