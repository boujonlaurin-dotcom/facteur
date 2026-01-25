#!/usr/bin/env python3
"""
Debug why user sees only one source in BREAKING mode.
Check user content exclusions.
"""
import asyncio
import os
import sys
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from dotenv import load_dotenv
load_dotenv()

async def debug_user():
    print("🔍 Debugging User Content Exclusions...")
    print("=" * 60)
    
    from sqlalchemy.ext.asyncio import create_async_engine
    from sqlalchemy import text
    from sqlalchemy.pool import NullPool
    
    db_url = os.environ.get('DATABASE_URL', '')
    if db_url.startswith('postgresql://'):
        db_url = db_url.replace('postgresql://', 'postgresql+asyncpg://', 1)
    engine = create_async_engine(db_url, poolclass=NullPool)
    
    async with engine.connect() as conn:
        # 1. List all users
        print("\n1️⃣ Users in system:")
        result = await conn.execute(text("""
            SELECT u.id, up.first_name, up.last_name, up.onboarding_completed
            FROM auth.users u
            LEFT JOIN user_profiles up ON u.id = up.user_id
            LIMIT 10
        """))
        users = result.fetchall()
        for i, row in enumerate(users):
            print(f"   [{i}] {row[0][:8]}... - {row[1]} {row[2]} (onboarded: {row[3]})")
        
        if not users:
            print("   No users found!")
            await engine.dispose()
            return
        
        # Use first user for debugging
        user_id = users[0][0]
        print(f"\n📌 Using user: {user_id[:8]}...")
        
        # 2. Check user content status counts
        print("\n2️⃣ User content status breakdown:")
        result = await conn.execute(text("""
            SELECT 
                status,
                is_hidden,
                is_saved,
                COUNT(*) as count
            FROM user_content_status
            WHERE user_id = :user_id
            GROUP BY status, is_hidden, is_saved
            ORDER BY count DESC
        """), {"user_id": user_id})
        for row in result:
            print(f"   status={row[0]}, hidden={row[1]}, saved={row[2]}: {row[3]} items")
        
        # 3. Count how many Hard News contents are excluded for this user
        now = datetime.now(timezone.utc)
        limit_date = now - timedelta(hours=12)
        
        print(f"\n3️⃣ Hard News contents in last 12h - exclusion analysis:")
        result = await conn.execute(text("""
            WITH hard_news AS (
                SELECT c.id, c.title, s.name as source_name
                FROM contents c
                JOIN sources s ON c.source_id = s.id
                WHERE s.is_curated = true
                  AND s.theme IN ('society', 'international', 'economy', 'politics')
                  AND c.published_at >= :limit_date
            ),
            user_excluded AS (
                SELECT content_id
                FROM user_content_status
                WHERE user_id = :user_id
                  AND (is_hidden = true OR is_saved = true OR status IN ('seen', 'consumed'))
            )
            SELECT 
                hn.source_name,
                COUNT(*) as total,
                SUM(CASE WHEN ue.content_id IS NOT NULL THEN 1 ELSE 0 END) as excluded,
                SUM(CASE WHEN ue.content_id IS NULL THEN 1 ELSE 0 END) as available
            FROM hard_news hn
            LEFT JOIN user_excluded ue ON hn.id = ue.content_id
            GROUP BY hn.source_name
            ORDER BY available DESC
        """), {"user_id": user_id, "limit_date": limit_date})
        
        total_available = 0
        for row in result:
            status = "✅" if row[3] > 0 else "❌"
            print(f"   {status} {row[0]}: {row[3]} available / {row[1]} total ({row[2]} excluded)")
            total_available += row[3]
        
        print(f"\n   TOTAL AVAILABLE: {total_available} articles")
        
        # 4. Sample some available contents
        print(f"\n4️⃣ Sample of available Hard News contents:")
        result = await conn.execute(text("""
            SELECT c.title, s.name, s.theme, c.published_at
            FROM contents c
            JOIN sources s ON c.source_id = s.id
            LEFT JOIN user_content_status ucs 
                ON ucs.content_id = c.id AND ucs.user_id = :user_id
            WHERE s.is_curated = true
              AND s.theme IN ('society', 'international', 'economy', 'politics')
              AND c.published_at >= :limit_date
              AND (ucs.id IS NULL OR (
                  ucs.is_hidden = false 
                  AND ucs.is_saved = false 
                  AND ucs.status NOT IN ('seen', 'consumed')
              ))
            ORDER BY c.published_at DESC
            LIMIT 10
        """), {"user_id": user_id, "limit_date": limit_date})
        
        for row in result:
            print(f"   • [{row[2]}] {row[1]}: {row[0][:60]}...")
    
    await engine.dispose()
    print("\n" + "=" * 60)

if __name__ == "__main__":
    asyncio.run(debug_user())
