
import asyncio
import sys
import os
from uuid import uuid4
from datetime import datetime, timedelta
from dotenv import load_dotenv

load_dotenv()
sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

from app.config import get_settings
from app.models.user import UserProfile, UserPreference, UserInterest
from app.models.source import Source, UserSource
from app.models.content import Content
from app.services.recommendation_service import RecommendationService
from app.models.enums import ReliabilityScore, ContentType, SourceType, BiasStance

# Helper to log
def log(msg):
    # Print to console AND file
    print(msg)
    with open("persona_results.log", "a") as f:
        f.write(msg + "\n")

async def create_dummy_data(session, user_id, persona_name, interests, trusted_sources_conf):
    """
    Creates a User with specific interests and trusted sources.
    Also creates a set of Candidates (Contents) to test scoring:
    - 1. Matching Theme + Trusted Source
    - 2. Matching Theme + Random Source
    - 3. Random Theme + Trusted Source
    - 4. Random Theme + Random Source (High Quality)
    - 5. Random Theme + Random Source (Low Quality)
    """
    log(f"\n--- 👤 Creating Persona: {persona_name} ---")
    
    # User Profile
    user = UserProfile(user_id=user_id, display_name=persona_name, onboarding_completed=True)
    session.add(user)
    
    # Interests
    for slug, weight in interests.items():
        session.add(UserInterest(user_id=user_id, interest_slug=slug, weight=weight))
        log(f"   Interest: {slug} (w={weight})")
        
    # Sources (We create fresh sources to ensure clean state)
    # We need to map 'conf' names to real source IDs to create UserSource
    created_sources = {} 
    
    # Create a pool of sources
    source_configs = [
        ("Source_Trusted_Tech", "tech", ReliabilityScore.HIGH),
        ("Source_Random_Tech", "tech", ReliabilityScore.MEDIUM),
        ("Source_Trusted_General", "politics", ReliabilityScore.HIGH), # Trusted but maybe wrong theme
        ("Source_HighQ_General", "politics", ReliabilityScore.HIGH),
        ("Source_LowQ_General", "politics", ReliabilityScore.LOW),
        ("Source_Viral_Trash", "entertainment", ReliabilityScore.LOW),
    ]
    
    for name, theme, rel in source_configs:
        s = Source(
            id=uuid4(), name=name, theme=theme, reliability_score=rel,
            url=f"http://{name}.com", feed_url=f"http://{name}.com/rss", type=SourceType.RSS
        )
        session.add(s)
        created_sources[name] = s
    
    await session.flush()
    
    # User Trusts specific sources
    for trusted_name in trusted_sources_conf:
        if trusted_name in created_sources:
            s = created_sources[trusted_name]
            session.add(UserSource(user_id=user_id, source_id=s.id))
            log(f"   Trusts: {s.name}")
            
    # Create Content Candidates (Recent)
    now = datetime.utcnow()
    contents = []
    
    # 1. Perfect Match (Interest + Trusted)
    c1 = Content(id=uuid4(), title=f"Perfect Match ({persona_name})", source_id=created_sources["Source_Trusted_Tech"].id, published_at=now, content_type=ContentType.ARTICLE)
    contents.append(c1)

    # 2. Interest Only
    c2 = Content(id=uuid4(), title=f"Interest Only ({persona_name})", source_id=created_sources["Source_Random_Tech"].id, published_at=now, content_type=ContentType.ARTICLE)
    contents.append(c2)

    # 3. Trust Only (Wrong Theme)
    c3 = Content(id=uuid4(), title=f"Trust Only ({persona_name})", source_id=created_sources["Source_Trusted_General"].id, published_at=now, content_type=ContentType.ARTICLE)
    contents.append(c3)

    # 4. Global High Quality (No Trust, No Interest)
    c4 = Content(id=uuid4(), title=f"Global Quality ({persona_name})", source_id=created_sources["Source_HighQ_General"].id, published_at=now, content_type=ContentType.ARTICLE)
    contents.append(c4)
    
    # 5. Generic/Trash
    c5 = Content(id=uuid4(), title=f"Trash/Viral", source_id=created_sources["Source_Viral_Trash"].id, published_at=now, content_type=ContentType.ARTICLE)
    contents.append(c5)

    session.add_all(contents)
    await session.commit()
    return contents

async def run_analysis():
    # Setup
    with open("persona_results.log", "w") as f:
        f.write("--- Persona Validation Start ---\n")

    settings = get_settings()
    engine = create_async_engine(settings.database_url, echo=False)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    
    async with async_session() as session:
        service = RecommendationService(session)
        
        # Scenario 1: The Tech Specialist
        # Likes Tech, Trusts "Source_Trusted_Tech"
        user1_id = uuid4()
        await create_dummy_data(
            session, 
            user1_id, 
            "Techie", 
            interests={"tech": 1.5}, 
            trusted_sources_conf=["Source_Trusted_Tech", "Source_Trusted_General"]
        )
        
        log(f"\n🔄 Generatin Feed for Techie...")
        feed1 = await service.get_feed(user_id=user1_id, limit=10)
        
        log(f"{'RANK':<4} | {'SCORE':<6} | {'TITLE':<30} | {'REASON'}")
        log("-" * 80)
        for i, c in enumerate(feed1):
             # To get exact score we would need to instrument the service again or guess.
             # We rely on rank order.
             reason = c.recommendation_reason.label if c.recommendation_reason else "N/A"
             log(f"#{i+1:<3} | {'?':<6} | {c.title:<30} | {reason}")


        # Cleanup
        # (For minimal impact, we could delete, but for debugging keeping them might be useful. 
        # But to be clean/repeatable:)
        # await session.execute("DELETE FROM user_profiles WHERE display_name IN ('Techie')") 
        # ... complicated with cascades. Let's just leave them or delete by ID.
        
        log("\n--- Analysis Complete ---")

if __name__ == "__main__":
    try:
        sys.stdout = open("persona_results.log", "a")
        sys.stderr = sys.stdout
        asyncio.run(run_analysis())
    except Exception as e:
        with open("persona_results_error.log", "a") as f:
            f.write(str(e))
