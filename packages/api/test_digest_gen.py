
import asyncio
import argparse
import sys
import uuid
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from sqlalchemy import text

# Add the parent directory to sys.path to allow imports from app
import os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from app.database import Base
from app.services.digest_service import DigestService
from app.config import get_settings

async def test_digest_generation(user_id_str):
    """Test digest generation for a specific user."""
    print(f"Testing digest generation for user: {user_id_str}")
    
    try:
        user_id = uuid.UUID(user_id_str)
    except ValueError:
        print(f"Error: Invalid UUID string: {user_id_str}")
        return

    # Setup database connection
    # Use the database URL from settings or environment
    settings = get_settings()
    database_url = settings.database_url
    print(f"Connecting to database...")
    
    engine = create_async_engine(database_url, echo=False)
    async_session = sessionmaker(
        engine, class_=AsyncSession, expire_on_commit=False
    )

    async with async_session() as session:
        try:
            # 1. Check User Streaks Schema
            print("\n1. Checking user_streaks schema...")
            result = await session.execute(text(
                "SELECT column_name FROM information_schema.columns WHERE table_name = 'user_streaks'"
            ))
            columns = [row[0] for row in result.fetchall()]
            required_cols = ['closure_streak', 'longest_closure_streak', 'last_closure_date']
            missing = [col for col in required_cols if col not in columns]
            
            if missing:
                print(f"❌ Schema validation failed. Missing columns: {missing}")
            else:
                print("✅ Schema validation passed.")

            # 2. Attempt Digest Generation
            print("\n2. Generating digest...")
            digest_service = DigestService(session)
            
            # Force generation by checking logic (we use get_or_create)
            digest = await digest_service.get_or_create_digest(user_id)
            
            if digest:
                print(f"✅ Digest generated successfully!")
                print(f"Digest ID: {digest.digest_id}")
                print(f"Items: {len(digest.items)}")
                for item in digest.items:
                    print(f" - [{item.rank}] {item.title} (Source: {item.source.name if item.source else 'Unknown'})")
            else:
                print("❌ Digest generation failed (returned None).")
                
        except Exception as e:
            print(f"❌ Exception during test: {e}")
            import traceback
            traceback.print_exc()
        finally:
            await session.close()
    
    await engine.dispose()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Test Digest Generation")
    parser.add_argument("user_id", help="UUID of the user to test")
    args = parser.parse_args()
    
    asyncio.run(test_digest_generation(args.user_id))
