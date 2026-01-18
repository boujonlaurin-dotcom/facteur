
import asyncio
import os
import sys
from sqlalchemy import select, func
from dotenv import load_dotenv

# Setup path and env similar to import script
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
load_dotenv(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".env"))

from app.database import async_session_maker, init_db
from app.models.source import Source

async def main():
    await init_db()
    async with async_session_maker() as session:
        # Count all
        total = await session.scalar(select(func.count(Source.id)))
        # Count curated
        curated = await session.scalar(select(func.count(Source.id)).where(Source.is_curated == True))
        # Count analyzed (non-curated)
        analyzed = await session.scalar(select(func.count(Source.id)).where(Source.is_curated == False))
        
        output = []
        output.append(f"--- SOURCE VERIFICATION ---")
        output.append(f"Total Sources: {total}")
        output.append(f"Curated (Catalog): {curated}")
        output.append(f"Analyzed (Comparison Only): {analyzed}")
        
        # List a few analyzed sources to confirm names
        if analyzed > 0:
            result = await session.execute(select(Source.name).where(Source.is_curated == False).limit(5))
            names = result.scalars().all()
            output.append(f"Sample Analyzed Sources: {names}")
            
        with open("verification.txt", "w") as f:
            f.write("\n".join(output))

if __name__ == "__main__":
    asyncio.run(main())
