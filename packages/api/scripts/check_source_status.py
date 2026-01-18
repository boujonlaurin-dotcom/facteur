import asyncio
import os
import sys

# Add parent directory to path to allow imports from app
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import select
from app.database import async_session_maker, init_db
from app.models.source import Source

async def check_source(name_fragment: str, file):
    async with async_session_maker() as session:
        result = await session.execute(select(Source).where(Source.name.ilike(f"%{name_fragment}%")))
        sources = result.scalars().all()
        if not sources:
            file.write(f"❌ No source found matching '{name_fragment}'\n")
            return
            
        for s in sources:
            file.write(f"🔎 Source: {s.name}\n")
            file.write(f"   URL: {s.url}\n")
            file.write(f"   Feed URL: {s.feed_url}\n")
            file.write(f"   is_curated: {s.is_curated}\n")
            file.write(f"   is_active: {s.is_active}\n")
            file.write(f"   bias_origin: {s.bias_origin}\n")
            file.write("-" * 20 + "\n")

async def main():
    with open("check_output.txt", "w") as f:
        f.write("Checking DB status...\n")
        await init_db()
        
        f.write("\nChecking RTL:\n")
        await check_source("RTL", f)
        
        f.write("\nChecking France Info:\n")
        await check_source("France Info", f)
        f.write("\nChecking TF1:\n")
        await check_source("TF1", f)

if __name__ == "__main__":
    asyncio.run(main())
