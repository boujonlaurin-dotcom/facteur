import asyncio
import os
import sys
from datetime import datetime

sys.path.append(os.getcwd())

from sqlalchemy import text, select
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

from app.config import get_settings
from app.services.recommendation_service import RecommendationService
from app.models.content import Content
from app.models.source import Source

async def main():
    settings = get_settings()
    engine = create_async_engine(settings.database_url)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    async with async_session() as session:
        # 1. Identify active user
        user_res = await session.execute(text("SELECT user_id FROM user_profiles LIMIT 1"))
        user_id = user_res.scalar()
        if not user_id:
            print("No user profiles found.")
            return
            
        print(f"MEASURE: Analyzing context for User {user_id}")
        
        # 2. Source Inventory (Total articles synced)
        print("\n--- MEASURE: Total Articles per Source ---")
        stmt = text("""
            SELECT s.name, COUNT(c.id) as count, MIN(c.published_at) as oldest, MAX(c.published_at) as newest
            FROM sources s
            LEFT JOIN contents c ON s.id = c.source_id
            GROUP BY s.name
            ORDER BY count DESC;
        """)
        res = await session.execute(stmt)
        for row in res:
            print(f"{row.name:30} | {row.count:5} articles | Newest: {row.newest}")

        # 3. Simulate Recommendation for this user
        print("\n--- MEASURE: Top 40 Recommended Items (Scoring Breakdown) ---")
        service = RecommendationService(session)
        feed = await service.get_feed(user_id, limit=40)
        
        for i, item in enumerate(feed):
            # Inspect image URL pattern
            img_url = item.thumbnail_url or "NONE"
            print(f"{i+1:2}. [{item.source.name[:20]:20}] {item.title[:40]:40}... | IMG: {img_url[:60]}")

        # 4. Image Quality Check
        print("\n--- MEASURE: Specific Image URL Patterns ---")
        stmt = text("""
            SELECT thumbnail_url, title, source_id
            FROM contents
            WHERE thumbnail_url IS NOT NULL
            LIMIT 10;
        """)
        res = await session.execute(stmt)
        for row in res:
            print(f"URL: {row.thumbnail_url}\n   Title: {row.title}\n")

    await engine.dispose()

if __name__ == "__main__":
    asyncio.run(main())
