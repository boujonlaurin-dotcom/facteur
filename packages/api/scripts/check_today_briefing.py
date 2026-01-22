import asyncio
import sys
import os
from datetime import datetime
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

# Adjust path to find app module
sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from app.config import get_settings
from app.models.daily_top3 import DailyTop3

async def check_briefing():
    settings = get_settings()
    db_url = settings.database_url
    
    if "+asyncpg" in db_url:
        db_url = db_url.replace("+asyncpg", "+psycopg")
    elif db_url.startswith("postgres://"):
        db_url = db_url.replace("postgres://", "postgresql+psycopg://", 1)
        
    engine = create_async_engine(db_url)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    
    async with async_session() as session:
        # Check today
        today_start = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
        stmt = select(DailyTop3).where(DailyTop3.generated_at >= today_start).limit(10)
        result = await session.execute(stmt)
        items = result.scalars().all()
        
        print(f"Found {len(items)} items for today ({today_start})")
        for item in items:
            print(f"User: {item.user_id}, Content: {item.content_id}, Rank: {item.rank}, Generated: {item.generated_at}")

        # Check yesterday for baseline
        yesterday_start = today_start.replace(day=today_start.day - 1)
        stmt_yesterday = select(DailyTop3).where(DailyTop3.generated_at >= yesterday_start, DailyTop3.generated_at < today_start).limit(5)
        result_yesterday = await session.execute(stmt_yesterday)
        items_yesterday = result_yesterday.scalars().all()
        print(f"Found {len(items_yesterday)} items for yesterday ({yesterday_start})")

if __name__ == "__main__":
    asyncio.run(check_briefing())
