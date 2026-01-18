import asyncio
import os
import sys

# Add parent directory to path to allow imports from app
sys.path.append(os.path.join(os.getcwd(), "packages/api"))

from sqlalchemy import select
from app.database import async_session_maker, init_db
from app.models.source import Source

async def main():
    if len(sys.argv) < 2:
        print("Usage: python check_source_details.py <source_name>")
        return
        
    name_fragment = sys.argv[1]
    
    await init_db()
    async with async_session_maker() as session:
        result = await session.execute(select(Source).where(Source.name.ilike(f"%{name_fragment}%")))
        sources = result.scalars().all()
        if not sources:
            print(f"❌ No source found matching '{name_fragment}'")
            return
            
        for s in sources:
            print(f"🔎 Source: {s.name}")
            print(f"   Description: {s.description}")
            print(f"   Scores: Indep={s.score_independence}, Rigor={s.score_rigor}, UX={s.score_ux}")
            print("-" * 20)

if __name__ == "__main__":
    asyncio.run(main())
