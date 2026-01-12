import asyncio
import sys
import os
from uuid import uuid4
from datetime import datetime
from dotenv import load_dotenv

load_dotenv()

# Add the parent directory to sys.path to make app modules importable
sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

from app.config import get_settings
from app.models.user import UserProfile, UserPreference, UserInterest
from app.services.recommendation_service import RecommendationService

async def run_simulation():
    # 1. Setup DB
    settings = get_settings()
    database_url = settings.database_url
    # Ensure standard postgresql driver for async (if needed, but sqlalchemy 1.4+ handles asyncpg in url usually)
    # The app code uses create_async_engine directly, let's copy that pattern if possible or just use the url.
    
    engine = create_async_engine(database_url, echo=False)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    async with async_session() as session:
        print("\n--- 🤖 Starting Recommendation Algorithm Simulation ---\n")
        
        # 2. Create Dummy User
        user_id = uuid4()
        print(f"👤 Creating temporary user: {user_id}")
        
        # Mock Profile
        user = UserProfile(
            user_id=user_id,
            age_range="25-34",
            gender="female",
            onboarding_completed=True
        )
        session.add(user)
        
        # Mock Interests (Behavioral Logic)
        # User likes Tech a lot (weight 1.5) and Politics a little (weight 1.0)
        interests = [
            UserInterest(user_id=user_id, interest_slug="tech", weight=1.5),
            UserInterest(user_id=user_id, interest_slug="politics", weight=1.0),
            UserInterest(user_id=user_id, interest_slug="culture", weight=0.8) # Getting bored of culture
        ]
        session.add_all(interests)
        
        # Mock Preferences (Static Logic)
        # Prefers Short content and Recent sources
        prefs = [
            UserPreference(user_id=user_id, preference_key="format_preference", preference_value="short"),
            UserPreference(user_id=user_id, preference_key="content_recency", preference_value="recent")
        ]
        session.add_all(prefs)
        
        await session.commit()
        
        # 3. Run Recommendation
        print("\n🔄 Generating Feed...")
        service = RecommendationService(session)
        feed = await service.get_feed(user_id=user_id, limit=20)
        
        print(f"\n✅ Feed generated with {len(feed)} items.\n")
        
        print(f"{'SCORE':<8} | {'REASON':<25} | {'TITLE'}")
        print("-" * 80)
        
        # 4. Display Results
        # We need to access the transient score hidden in the service logic?
        # Actually get_feed returns Content objects. The score was used for sorting.
        # But `recommendation_reason` is attached!
        
        for content in feed:
            reason_str = "N/A"
            if content.recommendation_reason:
                reason_str = f"{content.recommendation_reason.label} ({int(content.recommendation_reason.confidence * 100)}%)"
            
            # Note: We don't have the raw score here unless we modify get_feed to return it, 
            # but we can infer the rank.
            print(f"{'Top':<8} | {reason_str:<25} | {content.title[:40]}...")
            
        print("\n----------------------------------------------------------------")
        print("Analyze the results above to validate if 'Tech' and 'Short' contents are prioritized.")
        
        # Cleanup
        print("\n🧹 Cleaning up temporary user...")
        await session.delete(user)
        # Cascade delete should handle others, but let's be safe if no cascade
        # (Assuming cascade is set up in models, otherwise we leave junk)
        
        await session.commit()
        print("✨ Done.")

if __name__ == "__main__":
    asyncio.run(run_simulation())
