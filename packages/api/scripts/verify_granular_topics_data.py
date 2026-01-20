"""Verify that granular_topics are correctly populated in the database."""
from dotenv import load_dotenv
from pathlib import Path

load_dotenv(Path(__file__).parent.parent / ".env", override=True)

import asyncio
import os
import sys

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import select
from app.database import async_session_maker, init_db
from app.models.source import Source

async def verify_data():
    await init_db()
    
    async with async_session_maker() as session:
        # Check specific curated sources
        sources_to_check = ["France Info", "ScienceEtonnante", "Bon Pote", "Heu?reka"]
        
        print(f"🔍 Verifying granular_topics for: {', '.join(sources_to_check)}")
        
        stmt = select(Source).where(Source.name.in_(sources_to_check))
        result = await session.execute(stmt)
        sources = result.scalars().all()
        
        found_count = 0
        for source in sources:
            found_count += 1
            status = "✅" if source.granular_topics else "❌"
            print(f"{status} {source.name}: {source.granular_topics}")
            
        print(f"\nFound {found_count}/{len(sources_to_check)} sources.")
        
        # Check counts
        stmt_count = select(Source).where(Source.granular_topics.is_not(None))
        result_count = await session.execute(stmt_count)
        all_with_topics = result_count.scalars().all()
        print(f"📊 Total sources with granular_topics populated: {len(all_with_topics)}")

if __name__ == "__main__":
    asyncio.run(verify_data())
