import asyncio
import os
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from dotenv import load_dotenv
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from app.models.source import Source
from app.models.enums import BiasStance, ReliabilityScore, BiasOrigin

load_dotenv()
DATABASE_URL = os.getenv("DATABASE_URL")

async def verify():
    engine = create_async_engine(DATABASE_URL)
    AsyncSessionLocal = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    async with AsyncSessionLocal() as session:
        # Count sources by bias
        result = await session.execute(
            select(Source.bias_stance, func.count(Source.id))
            .group_by(Source.bias_stance)
        )
        print("📊 Sources by Bias Stance:")
        for bias, count in result.all():
            print(f"  {bias.value}: {count}")
        
        # Count sources by reliability
        result = await session.execute(
            select(Source.reliability_score, func.count(Source.id))
            .group_by(Source.reliability_score)
        )
        print("\n📊 Sources by Reliability:")
        for reliability, count in result.all():
            print(f"  {reliability.value}: {count}")
        
        # Show a few examples
        result = await session.execute(select(Source).limit(5))
        sources = result.scalars().all()
        print("\n📰 Sample Sources:")
        for source in sources:
            print(f"  - {source.name}: {source.bias_stance.value} / {source.reliability_score.value} ({source.bias_origin.value})")
    
    await engine.dispose()

if __name__ == "__main__":
    asyncio.run(verify())
