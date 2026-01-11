import asyncio
import os
import sys
from uuid import UUID

sys.path.append(os.getcwd())

from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

from app.config import get_settings
from app.services.recommendation_service import RecommendationService
from app.models.content import Content
from app.models.source import Source

# Mock User ID (we need a valid one, picking first user from DB)
async def get_test_user_id(session):
    result = await session.execute(text("SELECT user_id FROM user_profiles LIMIT 1"))
    return result.scalar()

async def main():
    settings = get_settings()
    engine = create_async_engine(settings.database_url)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    async with async_session() as session:
        user_id = await get_test_user_id(session)
        if not user_id:
            print("No users found in DB.")
            return

        print(f"Analyzing feed for User ID: {user_id}")

        # 0. Check User Preferences
        print("\n--- User Context ---")
        followed = await session.execute(text(f"SELECT s.name FROM user_sources us JOIN sources s ON us.source_id = s.id WHERE us.user_id = '{user_id}'"))
        print(f"Followed Sources: {[row.name for row in followed]}")
        
        interests = await session.execute(text(f"SELECT interest_slug FROM user_interests WHERE user_id = '{user_id}'"))
        print(f"Interests: {[row.interest_slug for row in interests]}")
        
        service = RecommendationService(session)
        
        # 1. Fetch Candidates (Raw)
        print("\n--- Raw Candidates (Top 10 most recent) ---")
        candidates = await service._get_candidates(user_id, limit_candidates=10)
        for c in candidates:
            print(f"[{c.published_at}] {c.source.name} - {c.title[:40]}...")

        # 2. Score Analysis
        print("\n--- Scored Feed (Top 25) ---")
        # We need to manually replicate scoring to see the breakdown, or just call get_feed
        # get_feed returns the final list. Let's inspect that first.
        feed = await service.get_feed(user_id, limit=25)
        
        for i, item in enumerate(feed):
            print(f"{i+1}. [{item.source.name}] {item.title[:50]}... (Date: {item.published_at})")
            
        # 3. Source Distribution in DB
        print("\n--- DB Source Distribution (Last 100 items) ---")
        stmt = text("""
            SELECT s.name, COUNT(*) as c 
            FROM contents c 
            JOIN sources s ON c.source_id = s.id 
            GROUP BY s.name 
            ORDER BY c DESC 
            LIMIT 10
        """)
        dist = await session.execute(stmt)
        for row in dist:
            print(f"{row.name}: {row.c}")

    await engine.dispose()

if __name__ == "__main__":
    asyncio.run(main())
