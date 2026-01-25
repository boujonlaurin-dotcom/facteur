import asyncio
import sys
import os
from uuid import uuid4

# Add app to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from dotenv import load_dotenv
load_dotenv()

from app.database import async_session_maker
from app.models.user import UserProfile
from app.models.source import Source
from app.models.content import Content
from app.models.user_personalization import UserPersonalization
from app.services.recommendation_service import RecommendationService
from sqlalchemy import select, delete

async def verify_personalization():
    print("🚀 Starting Backend Personalization Verification...")
    async with async_session_maker() as session:
        # 1. Setup Mock User (Fetch a real one or use hardcoded if known)
        res = await session.execute(select(UserProfile).limit(1))
        user = res.scalar_one_or_none()
        
        if not user:
            print("❌ No users found in DB. Creating a temporary user for testing...")
            # Create a temp user if none exists to ensure script runs
            user_id = uuid4()
            user = UserProfile(id=user_id, user_id=user_id, display_name="Test User") # Use same ID for both to be safe
            session.add(user)
            await session.commit()
            print(f"👤 Created temporary User: {user_id}")
        else:
            # Try using the Primary Key (id) instead of Auth ID (user_id) because typical FKs point to PK
            # and the error "not present in table" suggests mismatch.
            user_id = user.id 
            print(f"👤 Testing with existing User (PK): {user_id}")
        
        # Cleanup previous test data
        await session.execute(delete(UserPersonalization).where(UserPersonalization.user_id == user_id))
        await session.commit()

        # 2. Setup Mock Source & Content
        source = await session.scalar(select(Source).limit(1))
        if not source:
            print("❌ No source found in DB. Please run source ingestion first.")
            return

        print(f"📦 Testing with source: {source.name} ({source.id})")

        # 3. Fetch Feed WITHOUT Mute
        rec_service = RecommendationService(session)
        feed_response = await rec_service.get_feed(user_id)
        
        initial_count = len([c for c in feed_response if c.source.id == source.id])
        print(f"✅ Initial items from source: {initial_count}")

        # 4. Apply Mute via Personalization
        perso = UserPersonalization(user_id=user_id, muted_sources=[source.id])
        session.add(perso)
        await session.commit()
        print(f"🔇 Source '{source.name}' muted.")

        # 5. Fetch Feed WITH Mute
        feed_response_muted = await rec_service.get_feed(user_id)
        
        muted_items = [c for c in feed_response_muted if c.source.id == source.id]
        
        if len(muted_items) == 0:
            print("🎯 SUCCESS: Muted source items excluded or pushed so far down they are not in first page.")
        else:
            first_item = muted_items[0]
            if first_item.recommendation_reason:
                personalization_malus = any(
                    "Personalisation" in cb.label and cb.points < 0 
                    for cb in first_item.recommendation_reason.breakdown
                )
                if personalization_malus:
                    print(f"🎯 SUCCESS: Personalization malus applied! Score: {first_item.recommendation_reason.score_total}")
                else:
                    print("❌ FAILED: Item found but no personalization malus in breakdown.")
            else:
                 print("❌ FAILED: Item found but has no recommendation reason.")

        # Cleanup
        await session.execute(delete(UserPersonalization).where(UserPersonalization.user_id == user_id))
        await session.commit()
        print("🧹 Cleanup done.")

if __name__ == "__main__":
    asyncio.run(verify_personalization())
