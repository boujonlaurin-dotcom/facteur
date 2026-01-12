import asyncio
import os
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from dotenv import load_dotenv

load_dotenv()
DATABASE_URL = os.getenv("DATABASE_URL")

async def check_extension():
    engine = create_async_engine(DATABASE_URL)
    AsyncSessionLocal = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    async with AsyncSessionLocal() as session:
        # Check if pg_trgm is installed
        result = await session.execute(text("SELECT * FROM pg_extension WHERE extname = 'pg_trgm'"))
        ext = result.first()
        if ext:
            print("✅ pg_trgm extension is installed")
        else:
            print("❌ pg_trgm extension is NOT installed")
            print("Attempting to install...")
            try:
                await session.execute(text("CREATE EXTENSION pg_trgm"))
                await session.commit()
                print("✅ Successfully installed pg_trgm")
            except Exception as e:
                print(f"❌ Failed to install: {e}")
        
        # Test similarity function
        try:
            result = await session.execute(text("SELECT similarity('hello', 'hallo')"))
            sim = result.scalar()
            print(f"✅ Similarity function works: similarity('hello', 'hallo') = {sim}")
        except Exception as e:
            print(f"❌ Similarity function failed: {e}")
    
    await engine.dispose()

if __name__ == "__main__":
    asyncio.run(check_extension())
