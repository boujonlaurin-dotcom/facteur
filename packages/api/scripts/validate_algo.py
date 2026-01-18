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
    # Ensure using the async driver in the URL if not present. 
    # The config usually has it, but let's be safe or just use settings.database_url
    database_url = settings.database_url
    
    engine = create_async_engine(database_url, echo=False)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    async with async_session() as session:
        print("\n--- 🤖 Starting Recommendation Algorithm Simulation (Deep Dive) ---\n")
        
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
        interests = [
            UserInterest(user_id=user_id, interest_slug="tech", weight=1.5),
            UserInterest(user_id=user_id, interest_slug="politics", weight=1.0),
        ]
        session.add_all(interests)
        
        # Mock Preferences (Static Logic)
        prefs = [
            UserPreference(user_id=user_id, preference_key="format_preference", preference_value="short"),
            UserPreference(user_id=user_id, preference_key="content_recency", preference_value="recent")
        ]
        session.add_all(prefs)
        
        # Mock Followed Sources (to test "Source Suivie")
        # We need to find a real source ID from DB or create one. 
        # For this script to allow analysis of existing data, let's try to find a source to follow.
        # But first let's just commit the user.
        await session.commit()
        
        # 3. Initialize Service
        service = RecommendationService(session)
        
        # 4. Fetch Candidates (Using internal method to inspect them before final feed generation)
        print("\n🔍 Fetching 100 recent candidates...")
        # Accessing protected method for debugging purposes
        candidates = await service._get_candidates(
            user_id, 
            limit_candidates=100,
        )
        print(f"Found {len(candidates)} candidates.")

        # 5. Determine a source to 'follow' for the test if we have candidates
        followed_source_ids = set()
        if candidates:
            # Pick the source of the 10th candidate to be a "Followed Source"
            target_source = candidates[min(len(candidates)-1, 10)].source
            if target_source:
                followed_source_ids.add(target_source.id)
                print(f"🎯 Auto-following source for test: {target_source.name} ({target_source.theme})")

        # 6. Manual Scoring with Debug Context
        from app.services.recommendation.scoring_engine import ScoringContext
        
        now = datetime.utcnow()
        user_interests = {"tech", "politics"}
        user_interest_weights = {"tech": 1.5, "politics": 1.0}
        user_prefs_dict = {"format_preference": "short", "content_recency": "recent"}
        
        context = ScoringContext(
            user_profile=user,
            user_interests=user_interests,
            user_interest_weights=user_interest_weights,
            followed_source_ids=followed_source_ids, # Inject our fake followed source
            user_prefs=user_prefs_dict,
            now=now
        )
        
        print("\n📊 Scoring & Analyzing top candidates...\n")
        
        scored_items = []
        for content in candidates:
            score = service.scoring_engine.compute_score(content, context)
            scored_items.append((content, score))
            
        # Sort by score
        scored_items.sort(key=lambda x: x[1], reverse=True)
        
        # Print Detailed Report for Top 20
        print(f"{'RANK':<4} | {'SCORE':<6} | {'SOURCE (Themes)':<30} | {'DETAILS (Layer Breakdown)'}")
        print("-" * 140)
        
        for i, (content, total_score) in enumerate(scored_items[:20]):
            reasons = context.reasons.get(content.id, [])
            
            # Combine reasons into a readable string
            details_parts = []
            for r in reasons:
                layer = r['layer']
                pts = r['score_contribution']
                info = r['details']
                details_parts.append(f"[{layer}: {pts:+.0f} {info}]")
                
            details_str = " ".join(details_parts)
            
            source_info = "Unknown"
            if content.source:
                source_lbl = f"{content.source.name}"
                if content.source.id in followed_source_ids:
                    source_lbl += " (FOLLOWED)"
                if content.source.reliability_score == 'high':  # Check enum value mapping if string
                    source_lbl += " (HIGH_QUAL)"
                source_info = f"{source_lbl} [{content.source.theme}]"
                
            print(f"#{i+1:<3} | {total_score:<6.1f} | {source_info:<30} | {details_str}")
            
        print("\n----------------------------------------------------------------")
        
        # Cleanup
        print("\n🧹 Cleaning up temporary user...")
        await session.delete(user)
        # Manually delete related preferences/interests if cascade isn't automatic (check models)
        # For this script relying on transaction rollback might be safer but `commit` was called.
        # Let's assume cascade works or it's fine for a dev script.
        
        await session.commit()
        print("✨ Done.")


# Helper to log to file and console
def log(msg):
    print(msg)
    with open("algo_results.log", "a") as f:
        f.write(msg + "\n")

if __name__ == "__main__":
    # Clear log file
    with open("algo_results.log", "w") as f:
        f.write("--- Log Start ---\n")
        
    try:
        # Patch print ? No, just use log() or redirect stdout
        # Redirect stdout/stderr to file
        sys.stdout = open("algo_results.log", "a")
        sys.stderr = sys.stdout
        
        asyncio.run(run_simulation())
    except Exception as e:
        with open("algo_results_error.log", "a") as f:
           f.write(f"CRITICAL ERROR: {str(e)}\n")
        print(f"CRITICAL ERROR: {str(e)}")

