import asyncio
import sys
import os
from datetime import datetime, timedelta
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

# Adjust path to find app module
sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from app.config import get_settings
from app.models.content import Content

async def check_content_volume():
    settings = get_settings()
    db_url = settings.database_url
    
    if "+asyncpg" in db_url:
        db_url = db_url.replace("+asyncpg", "+psycopg")
    elif db_url.startswith("postgres://"):
        db_url = db_url.replace("postgres://", "postgresql+psycopg://", 1)
        
    engine = create_async_engine(db_url)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    
    async with async_session() as session:
        # Check count for Jan 21
        yesterday_start = datetime(2026, 1, 21, 0, 0, 0)
        yesterday_end = yesterday_start + timedelta(days=1)
        
        stmt = select(func.count()).select_from(Content).where(Content.published_at >= yesterday_start, Content.published_at < yesterday_end)
        count = (await session.execute(stmt)).scalar()
        
        print(f"Contents published on Jan 21: {count}")

        # Check today (Jan 22) so far
        today_start = datetime(2026, 1, 22, 0, 0, 0)
        stmt_today = select(func.count()).select_from(Content).where(Content.published_at >= today_start)
        count_today = (await session.execute(stmt_today)).scalar()
        print(f"Contents published on Jan 22 so far: {count_today}")

if __name__ == "__main__":
    asyncio.run(check_content_volume())
