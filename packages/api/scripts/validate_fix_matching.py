"""Valide que le fix du matching fonctionne avec les personas existants."""
import asyncio
import os
import sys

from dotenv import load_dotenv
from pathlib import Path

# Load .env
load_dotenv(Path(__file__).parent.parent / ".env", override=True)

from sqlalchemy import select
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from app.config import get_settings
from app.services.recommendation_service import RecommendationService
from app.models.user import UserInterest, UserProfile
from app.models.content import Content

async def validate_fix():
    settings = get_settings()
    engine = create_async_engine(settings.database_url, echo=False)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    async with async_session() as session:
        service = RecommendationService(session)
        
        # Récupérer un user avec interests
        user_profile = await session.scalar(
            select(UserProfile)
            .where(UserProfile.onboarding_completed == True)
            .limit(1)
        )
        
        if not user_profile:
            msg = "❌ Aucun user avec onboarding complété"
            print(msg)
            with open("validation_result.txt", "w") as f: f.write(msg)
            return
        
        # Récupérer ses interests
        interests = await session.scalars(
            select(UserInterest).where(UserInterest.user_id == user_profile.user_id)
        )
        user_interests = {i.interest_slug for i in interests}
        
        print(f"✅ User: {user_profile.user_id}")
        print(f"   Interests: {user_interests}")
        
        # Générer feed
        feed = await service.get_feed(user_profile.user_id, limit=20)
        
        # Compter combien d'articles ont un theme match
        matched_count = 0
        for content in feed:
            if content.recommendation_reason and "theme match" in content.recommendation_reason.label.lower():
                matched_count += 1
            # Check old label just in case
            elif content.recommendation_reason and "intérêts" in content.recommendation_reason.label.lower():
                 matched_count += 1

        match_rate = matched_count / len(feed) if feed else 0
        
        output_lines = []
        output_lines.append(f"   Feed size: {len(feed)}")
        output_lines.append(f"   Theme matches: {matched_count} ({match_rate*100:.1f}%)")
        
        if match_rate >= 0.40:
             output_lines.append(f"✅ PASS : Match rate acceptable ({match_rate*100:.1f}%)")
        else:
             output_lines.append(f"❌ FAIL : Match rate trop faible: {match_rate*100:.1f}% (attendu ≥40%)")

        print("\n".join(output_lines))
        with open("validation_result.txt", "w") as f:
            f.write("\n".join(output_lines))

if __name__ == "__main__":
    try:
        print("🚀 Starting validation script...")
        asyncio.run(validate_fix())
    except Exception as e:
        import traceback
        msg = f"CRITICAL ERROR: {e}\n{traceback.format_exc()}"
        print(msg)
        with open("validation_result.txt", "w") as f:
            f.write(msg)
