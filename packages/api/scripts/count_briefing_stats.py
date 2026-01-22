import asyncio
import sys
import os
from datetime import datetime
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

# Adjust path to find app module
sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from app.config import get_settings
from app.models.daily_top3 import DailyTop3
from app.models.user import UserProfile

async def check_counts():
    settings = get_settings()
    db_url = settings.database_url
    
    if "+asyncpg" in db_url:
        db_url = db_url.replace("+asyncpg", "+psycopg")
    elif db_url.startswith("postgres://"):
        db_url = db_url.replace("postgres://", "postgresql+psycopg://", 1)
        
    engine = create_async_engine(db_url)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    
    async with async_session() as session:
        # Count users
        stmt_users = select(func.count()).select_from(UserProfile).where(UserProfile.onboarding_completed == True)
        user_count = (await session.execute(stmt_users)).scalar()
        
        # Count today's briefings
        today_start = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
        stmt_briefings = select(func.count(DailyTop3.user_id.distinct())).where(DailyTop3.generated_at >= today_start)
        briefing_user_count = (await session.execute(stmt_briefings)).scalar()
        
        stmt_total_briefing_rows = select(func.count()).select_from(DailyTop3).where(DailyTop3.generated_at >= today_start)
        total_rows = (await session.execute(stmt_total_briefing_rows)).scalar()

        print(f"Users with onboarding completed: {user_count}")
        print(f"Users who received a briefing today: {briefing_user_count}")
        print(f"Total briefing rows today: {total_rows}")

if __name__ == "__main__":
    asyncio.run(check_counts())
