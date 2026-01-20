"""
Script de diagnostic profond pour un utilisateur spécifique.
Usage: python packages/api/scripts/debug_user_feed.py "email@example.com"
"""
import asyncio
import sys
import os
from uuid import UUID
from sqlalchemy import select
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

# Setup path
sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from app.config import get_settings
from app.models.user import UserProfile, UserInterest
from app.models.content import Content
from app.services.recommendation_service import RecommendationService
from app.services.recommendation.theme_mapper import get_user_slugs_for_source, THEME_TO_USER_SLUGS

async def debug_user(email: str):
    print(f"🔍 Debugging User: {email}")
    settings = get_settings()
    engine = create_async_engine(settings.database_url, echo=False)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    async with async_session() as session:
        # 1. Fetch User ID from Profile (via email lookup if possible, otherwise list all for manual pick)
        # Assuming we don't have email in UserProfile directly visible here easily, let's look at recent profiles?
        # Actually UserProfile is usually linked to Auth... let's try to find by some metadata or just pick the most recent one if email is hard to map without Auth table.
        # UserProfile usually has display_name or similar.
        
        # NOTE: UserProfile schema check needed.
        # Let's list top 5 users + interests to find our guy.
        stmt = select(UserProfile).options(selectinload(UserProfile.interests)).limit(10)
        profiles = (await session.scalars(stmt)).all()
        
        target_user = None
        for p in profiles:
             # Basic heuristic since we might not have email in UserProfile model
             print(f"   Candidate: {p.user_id} - Name: {p.display_name}")
             # If exact match or we just take the first one with interests
             if p.interests:
                 target_user = p
                 # break # Don't break, see all
        
        if not target_user:
            print("❌ No user found with interests.")
            return

        print(f"\n✅ Selected Target User: {target_user.user_id} ({target_user.display_name})")
        
        # 2. Print Interests
        interests = {i.interest_slug for i in target_user.interests}
        print(f"   User Interests Slugs: {interests}")
        
        # 3. Fetch Feed Candidates
        service = RecommendationService(session)
        # We peek at _get_candidates internal logic or just call get_feed
        print("\n🔄 Generating Feed...")
        feed = await service.get_feed(target_user.user_id, limit=50)
        
        print(f"   Feed Size: {len(feed)}")
        
        # 4. Analyze first 10 items
        print("\n🧐 Analyzing Top 10 Items:")
        for i, content in enumerate(feed[:10]):
            source = content.source
            if not source:
                print(f"   #{i} [NO SOURCE] {content.title}")
                continue
                
            src_theme = source.theme
            mapped_slugs = get_user_slugs_for_source(source)
            
            # Manual Match Check
            intersection = mapped_slugs & interests
            is_match = len(intersection) > 0
            
            ui_reason = content.recommendation_reason.label if content.recommendation_reason else "None"
            
            print(f"   #{i} [{ui_reason}]")
            print(f"       Title: {content.title}")
            print(f"       Source: {source.name}")
            print(f"       Src Theme (Raw): '{src_theme}'")
            print(f"       Mapped Slugs: {mapped_slugs}")
            print(f"       Match Expected?: {is_match} (Intersection: {intersection})")
            
            if is_match and "Theme match" not in str(ui_reason) and "Sujet" not in str(ui_reason) and "Vos intérêts" not in str(ui_reason):
                 print(f"       ⚠️ PROBLEM: Should match but UI shows '{ui_reason}'")

if __name__ == "__main__":
    import sys
    email = sys.argv[1] if len(sys.argv) > 1 else "default"
    asyncio.run(debug_user(email))
