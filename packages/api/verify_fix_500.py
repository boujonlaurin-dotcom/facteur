import asyncio
import uuid
import structlog
from app.database import engine
from app.services.recommendation_service import RecommendationService
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.content import Content
from sqlalchemy import select

async def main():
    print("🔌 Connecting to DB...")
    async with AsyncSession(engine) as session:
        # Create service
        service = RecommendationService(session)
        
        # Verify if there is at least one content
        result = await session.execute(select(Content).limit(1))
        content = result.scalars().first()
        if not content:
            print("⚠️ DB is empty, cannot verify thoroughly but will test query generation.")
        else:
            print("✅ DB connection OK. Content table has data.")
        
        print("Running _get_candidates with muted_topics...")
        try:
            # We pass a dummy user_id
            user_id = uuid.uuid4()
            
            # This triggered the 500 error before fix due to NULL topics handling
            candidates = await service._get_candidates(
                user_id=user_id,
                limit_candidates=10,
                muted_topics={'tech', 'politics'}, # Dummy topics to trigger overlap check
                followed_source_ids=set(),
                muted_sources=set(),
                muted_themes=set()
            )
            print(f"✅ Success! Query executed without error. Candidates found: {len(candidates)}")
            
        except Exception as e:
            print(f"❌ Failed with error: {e}")
            import traceback
            traceback.print_exc()
            exit(1)

if __name__ == "__main__":
    asyncio.run(main())
