"""Script to clean up duplicate briefing entries.

Keeps only the first entry per (user_id, rank, date) combination.
"""
import asyncio
import sys
import os
from datetime import datetime
from collections import defaultdict
from sqlalchemy import select, delete
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

# Adjust path to find app module
sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from app.config import get_settings
from app.models.daily_top3 import DailyTop3


async def cleanup_duplicates():
    """Remove duplicate briefing entries, keeping only the first one per (user, rank, date)."""
    print("🧹 Starting duplicate cleanup...")
    
    settings = get_settings()
    db_url = settings.database_url
    
    if "+asyncpg" in db_url:
        db_url = db_url.replace("+asyncpg", "+psycopg")
    elif db_url.startswith("postgres://"):
        db_url = db_url.replace("postgres://", "postgresql+psycopg://", 1)
        
    engine = create_async_engine(db_url)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    
    async with async_session() as session:
        # Fetch all entries
        stmt = select(DailyTop3).order_by(DailyTop3.user_id, DailyTop3.generated_at, DailyTop3.rank)
        result = await session.execute(stmt)
        all_items = result.scalars().all()
        
        print(f"📊 Found {len(all_items)} total entries")
        
        # Group by (user_id, rank, date)
        groups: dict[tuple, list] = defaultdict(list)
        for item in all_items:
            key = (item.user_id, item.rank, item.generated_at.date())
            groups[key].append(item)
        
        # Find duplicates (groups with more than 1 entry)
        duplicates_to_delete = []
        for key, items in groups.items():
            if len(items) > 1:
                # Keep the first one, delete the rest
                for item in items[1:]:
                    duplicates_to_delete.append(item.id)
        
        print(f"🔍 Found {len(duplicates_to_delete)} duplicate entries to delete")
        
        if duplicates_to_delete:
            # Delete duplicates
            for dup_id in duplicates_to_delete:
                await session.execute(delete(DailyTop3).where(DailyTop3.id == dup_id))
            
            await session.commit()
            print(f"✅ Deleted {len(duplicates_to_delete)} duplicates")
        else:
            print("✅ No duplicates found")
        
        # Verify
        result_after = await session.execute(select(DailyTop3))
        remaining = len(result_after.scalars().all())
        print(f"📊 Remaining entries: {remaining}")


if __name__ == "__main__":
    asyncio.run(cleanup_duplicates())
