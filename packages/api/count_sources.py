import asyncio
import os
from sqlalchemy import select, func
from app.database import async_session_maker, init_db
from app.models.source import Source

async def count_sources():
    await init_db()
    async with async_session_maker() as session:
        # Total sources
        total = await session.execute(select(func.count()).select_from(Source))
        total_count = total.scalar()
        
        # Non-curated sources (is_curated=False)
        non_curated = await session.execute(select(func.count()).select_from(Source).where(Source.is_curated == False))
        non_curated_count = non_curated.scalar()
        
        # Recent sources (last 5 min) - if we had a created_at, but let's just use counts for now
        
        print(f"TOTAL_SOURCES: {total_count}")
        print(f"NON_CURATED_SOURCES: {non_curated_count}")

if __name__ == "__main__":
    import sys
    # Ensure app is in path
    sys.path.append(os.getcwd())
    asyncio.run(count_sources())
