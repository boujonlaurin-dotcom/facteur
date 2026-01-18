import asyncio
import os
import sys

# Add parent directory to path to allow imports from app
sys.path.append(os.path.join(os.getcwd(), "packages/api"))

from sqlalchemy import select
from app.database import async_session_maker, init_db
from app.models.source import Source

async def main():
    name_fragment = "Bon Pote"
    await init_db()
    async with async_session_maker() as session:
        result = await session.execute(select(Source).where(Source.name.ilike(f"%{name_fragment}%")))
        sources = result.scalars().all()
        
        # Write results to a file that is NOT gitignored
        with open("db_check_result.txt", "w") as f:
            if not sources:
                f.write(f"❌ No source found matching '{name_fragment}'\n")
            else:
                for s in sources:
                    f.write(f"🔎 Source: {s.name}\n")
                    f.write(f"   Description: {s.description}\n")
                    f.write(f"   Scores: Indep={s.score_independence}, Rigor={s.score_rigor}, UX={s.score_ux}\n")
                    f.write("-" * 20 + "\n")

if __name__ == "__main__":
    asyncio.run(main())
