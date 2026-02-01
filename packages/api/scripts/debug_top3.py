
import asyncio
import os
import sys

# Add parent directory to path to allow importing app modules
sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from app.database import async_session_maker
from app.workers.top3_job import generate_daily_top3_job
from app.models.daily_top3 import DailyTop3
from app.models.user import UserProfile
from sqlalchemy import select, delete
from sqlalchemy.orm import selectinload

async def debug_top3():
    print("🚀 Starting Debug Top 3 Script")
    
    async with async_session_maker() as session:
        # 1. Clean up previous run for cleaner debug (Optional, maybe for a specific test user?)
        stmt = select(UserProfile).where(UserProfile.onboarding_completed == True).limit(1)
        result = await session.execute(stmt)
        user = result.scalar_one_or_none()
        
        if not user:
            print("❌ No user found in DB!")
            return

        print(f"👤 Testing for user: {user.user_id} ({user.display_name})")
        
        # Clean existing top3 for today for this user?
        # No, let's just run the job. It has ON CONFLICT DO NOTHING.
        # But to verify it works, we might want to clear it first if we want to regenerate.
        
        print("🧹 Cleaning existing DailyTop3 for this user (for test purpose)...")
        # We delete ALL top3 for this user to be sure
        await session.execute(delete(DailyTop3).where(DailyTop3.user_id == user.user_id))
        await session.commit()
        
        # 2. Run the Job
        print("\n⚙️ Running generate_daily_top3_job(trigger_manual=True)...")
        try:
            await generate_daily_top3_job(trigger_manual=True)
        except Exception as e:
            print(f"❌ Job crashed: {e}")
            import traceback
            traceback.print_exc()
            return

        # 3. Verify Results
        print("\n🔍 Verifying results in DB...")
        stmt = (
            select(DailyTop3)
            .options(selectinload(DailyTop3.content))
            .where(DailyTop3.user_id == user.user_id)
            .order_by(DailyTop3.rank)
        )
        result = await session.execute(stmt)
        rows = result.scalars().all()
        
        if not rows:
            print("❌ No DailyTop3 items found for user even after job!")
        else:
            print(f"✅ Found {len(rows)} items:")
            for row in rows:
                print(f"   #{row.rank} [{row.top3_reason}] {row.content.title} (Score?)")
                print(f"      Generated At: {row.generated_at}")

if __name__ == "__main__":
    asyncio.run(debug_top3())
