import asyncio
import sys
import os
from datetime import datetime
from sqlalchemy import select
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

# Adjust path to find app module
sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from app.config import get_settings
from app.models.daily_top3 import DailyTop3

async def inspect_briefings():
    settings = get_settings()
    db_url = settings.database_url
    
    if "+asyncpg" in db_url:
        db_url = db_url.replace("+asyncpg", "+psycopg")
    elif db_url.startswith("postgres://"):
        db_url = db_url.replace("postgres://", "postgresql+psycopg://", 1)
        
    engine = create_async_engine(db_url)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    
    async with async_session() as session:
        today_start = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
        stmt = select(DailyTop3).where(DailyTop3.generated_at >= today_start).order_by(DailyTop3.user_id, DailyTop3.rank)
        result = await session.execute(stmt)
        items = result.scalars().all()
        
        current_user = None
        user_items = []
        for item in items:
            if item.user_id != current_user:
                if current_user:
                    print(f"User {current_user}: {[i.rank for i in user_items]} at {[i.generated_at for i in user_items]}")
                current_user = item.user_id
                user_items = [item]
            else:
                user_items.append(item)
        if current_user:
            print(f"User {current_user}: {[i.rank for i in user_items]} at {[i.generated_at for i in user_items]}")

if __name__ == "__main__":
    asyncio.run(inspect_briefings())
