import sys
import os
import asyncio
from uuid import uuid4

# Setup path to include packages/api
# We assume the script is in docs/qa/scripts/
# So we need to go up 3 levels to root, then into packages/api
project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../..'))
api_path = os.path.join(project_root, 'packages/api')
sys.path.append(api_path)

# Verify import
try:
    from app.database import async_session_maker
    from app.services.recommendation_service import RecommendationService
    from app.models.content import Content
except ImportError as e:
    print(f"Error importing app modules: {e}")
    print(f"PYTHONPATH: {sys.path}")
    sys.exit(1)

async def main():
    print("Verifying Personalization Fix...")
    
    try:
        async with async_session_maker() as session:
            service = RecommendationService(session)
            
            # Helper to print query (if possible) or just status
            # RecommendationService._get_candidates builds a query and executes it.
            # We want to ensure it doesn't crash.
            
            # 1. Test with muted_topics
            print("\n1. Testing with muted_topics (Verifying 500 fix)...")
            user_id = uuid4()
            muted_topics = {"ai", "crypto"}
            
            try:
                candidates = await service._get_candidates(
                    user_id=user_id, 
                    limit_candidates=10, 
                    muted_topics=muted_topics
                )
                print(f"✅ Success! Query executed with muted_topics. Candidates found: {len(candidates)}")
            except Exception as e:
                print(f"❌ FAILED with muted_topics: {e}")
                raise e

            # 2. Test with muted_themes
            print("\n2. Testing with muted_themes (Verifying SQL generation)...")
            muted_themes = {"tech", "politics"}
            
            try:
                candidates = await service._get_candidates(
                    user_id=user_id, 
                    limit_candidates=10, 
                    muted_themes=muted_themes
                )
                print(f"✅ Success! Query executed with muted_themes. Candidates found: {len(candidates)}")
            except Exception as e:
                print(f"❌ FAILED with muted_themes: {e}")
                raise e
            
    except Exception as e:
        print(f"\nCRITICAL FAILURE: {e}")
        sys.exit(1)

if __name__ == "__main__":
    if "DATABASE_URL" not in os.environ:
        print("Error: DATABASE_URL must be set.")
        # Try to suggest sourcing it
        print("Tip: Run with 'export DATABASE_URL=... && python ...'")
        sys.exit(1)
    
    print(f"Using DB: {os.environ['DATABASE_URL'].split('@')[-1]}")
    
    asyncio.run(main())
