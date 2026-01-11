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

async def main():
    settings = get_settings()
    engine = create_async_engine(settings.database_url)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    async with async_session() as session:
        # Get all users
        users_res = await session.execute(text("SELECT user_id, display_name FROM user_profiles"))
        users = users_res.all()
        
        for u in users:
            print(f"\n===== ANALYZING USER: {u.display_name} ({u.user_id}) =====")
            
            # Followed Sources
            followed = await session.execute(text(f"SELECT s.name FROM user_sources us JOIN sources s ON us.source_id = s.id WHERE us.user_id = '{u.user_id}'"))
            print(f"Followed: {[row.name for row in followed]}")
            
            # Interests
            interests = await session.execute(text(f"SELECT interest_slug FROM user_interests WHERE user_id = '{u.user_id}'"))
            print(f"Interests: {[row.interest_slug for row in interests]}")
            
            # Mock Feed Generate
            service = RecommendationService(session)
            feed = await service.get_feed(u.user_id, limit=20)
            
            print("Top 20 Feed Composition:")
            counts = {}
            for item in feed:
                counts[item.source.name] = counts.get(item.source.name, 0) + 1
            
            for source, count in counts.items():
                print(f"  - {source}: {count}")
                
            if feed:
                print(f"  First Item: {feed[0].title[:50]} (Source: {feed[0].source.name})")

    await engine.dispose()

if __name__ == "__main__":
    asyncio.run(main())
