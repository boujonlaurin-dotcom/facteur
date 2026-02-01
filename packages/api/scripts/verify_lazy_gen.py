
import asyncio
import sys
import os

# Add parent directory to path to allow importing app modules
sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from app.database import async_session_maker, engine
from app.services.briefing_service import BriefingService
from app.models.daily_top3 import DailyTop3
from app.models.user import UserProfile
from sqlalchemy import select, delete
from uuid import UUID

async def verify_lazy_gen():
    print("🚀 Starting Recursive Verification of Lazy Gen...")
    
    async with async_session_maker() as session:
        # A. Find Target User
        stmt = select(UserProfile).where(UserProfile.onboarding_completed == True).limit(1)
        user = (await session.execute(stmt)).scalar_one_or_none()
        
        if not user:
            print("❌ No eligible user found for verification.")
            return False
            
        print(f"👤 Target User: {user.user_id} ({user.display_name})")
        
        # B. Clean Slate (Delete today's briefing)
        await session.execute(delete(DailyTop3).where(DailyTop3.user_id == user.user_id))
        await session.commit()
        print("🧹 Briefing wiped for user.")
        
        # C. Trigger Lazy Generation
        print("⚡️ Calling BriefingService.get_or_create_briefing...")
        service = BriefingService(session)
        items = await service.get_or_create_briefing(user.user_id)
        
        if not items:
            print("❌ Service returned empty items!")
            return False
            
        print(f"✅ Service returned {len(items)} items:")
        for item in items:
            print(f"   - #{item['rank']} [{item['reason']}] {item['content'].title[:50]}...")
            
        # D. Verify Persistence
        stmt_verify = select(DailyTop3).where(DailyTop3.user_id == user.user_id)
        rows = (await session.execute(stmt_verify)).scalars().all()
        
        if len(rows) != len(items):
            print(f"❌ Persistence Mismatch! Returned {len(items)} but found {len(rows)} in DB.")
            return False
            
        print("✅ DB Persistence confirmed.")
        return True

if __name__ == "__main__":
    try:
        success = asyncio.run(verify_lazy_gen())
        if success:
            sys.exit(0)
        else:
            sys.exit(1)
    except Exception as e:
        print(f"💥 Crash: {e}")
        sys.exit(1)
