import asyncio
import os
from sqlalchemy import select
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from dotenv import load_dotenv
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from app.models.source import Source

load_dotenv()
DATABASE_URL = os.getenv("DATABASE_URL")

async def check():
    engine = create_async_engine(DATABASE_URL)
    AsyncSessionLocal = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    async with AsyncSessionLocal() as session:
        result = await session.execute(select(Source).limit(1))
        source = result.scalars().first()
        if source:
            print(f"Source type in DB: {source.type}")
            # Check the raw value if possible
            from sqlalchemy import text
            res = await session.execute(text("SELECT type FROM sources LIMIT 1"))
            raw_val = res.scalar()
            print(f"Raw type value in DB: {raw_val}")
    await engine.dispose()

if __name__ == "__main__":
    asyncio.run(check())
