import asyncio
import os
import sys
from datetime import date, timedelta, datetime
from uuid import uuid4

# Add package root to path
sys.path.append(os.path.join(os.getcwd(), "packages/api"))

from sqlalchemy import select, delete
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

from app.database import Base
from app.models.user import UserProfile, UserStreak
from app.models.content import UserContentStatus, Content
from app.models.source import Source
from app.models.enums import ContentStatus, ContentType, SourceType
from app.services.streak_service import StreakService
from app.services.content_service import ContentService
from app.schemas.content import ContentStatusUpdate
from dotenv import load_dotenv

# Load env
load_dotenv(os.path.join(os.getcwd(), "packages/api/.env"))
DATABASE_URL = os.getenv("DATABASE_URL")

async def verify_streak():
    engine = create_async_engine(DATABASE_URL)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    user_id = uuid4()
    content_id = uuid4()

    print(f"🧪 Starting Streak Verification for User {user_id}")

    async with async_session() as session:
        # 1. Setup User
        print("   Creating dummy user...")
        # We need a profile usually
        profile = UserProfile(id=uuid4(), user_id=user_id)
        session.add(profile)

        # Create dummy Source and Content
        print("   Creating dummy source and content...")
        source = Source(
            id=uuid4(),
            name="Test Source",
            url="http://test.com",
            feed_url="http://test.com/feed",
            type=SourceType.ARTICLE,
            is_active=True,
            theme="Tech"
        )
        session.add(source)
        
        content = Content(
            id=content_id,
            source_id=source.id,
            title="Test Content",
            url="http://test.com/1",
            published_at=datetime.utcnow(),
            content_type=ContentType.ARTICLE,
            guid="test-guid-1"
        )
        session.add(content)
        
        # Another content for Test 2
        content2 = Content(
            id=uuid4(),
            source_id=source.id,
            title="Test Content 2",
            url="http://test.com/2",
            published_at=datetime.utcnow(),
            content_type=ContentType.ARTICLE,
            guid="test-guid-2"
        )
        session.add(content2)

        await session.commit()

        streak_service = StreakService(session)
        content_service = ContentService(session)

        # ---------------------------------------------------------
        # CASE 1: First Consumption (Start Streak)
        # ---------------------------------------------------------
        print("\n📝 TEST 1: First Consumption (Expect Streak -> 1)")
        await content_service.update_content_status(
            user_id, 
            content_id, 
            ContentStatusUpdate(status=ContentStatus.CONSUMED, time_spent_seconds=60)
        )
        await session.commit()

        streak = await streak_service.get_streak(str(user_id))
        print(f"   Current Streak: {streak.current_streak}")
        assert streak.current_streak == 1, f"Expected 1, got {streak.current_streak}"
        print("   ✅ Passed")

        # ---------------------------------------------------------
        # CASE 2: Same Day Consumption (Idempotency)
        # ---------------------------------------------------------
        print("\n📝 TEST 2: Same Day Consumption (Expect Streak -> 1)")
        await content_service.update_content_status(
            user_id, 
            content2.id, # Different content
            ContentStatusUpdate(status=ContentStatus.CONSUMED, time_spent_seconds=60)
        )
        await session.commit()

        streak = await streak_service.get_streak(str(user_id))
        print(f"   Current Streak: {streak.current_streak}")
        assert streak.current_streak == 1, f"Expected 1, got {streak.current_streak}"
        print("   ✅ Passed")

        # ---------------------------------------------------------
        # CASE 3: Consecutive Day (Increment)
        # ---------------------------------------------------------
        print("\n📝 TEST 3: Consecutive Day Simulation (Expect Streak -> 2)")
        # Manually backdate the last activity to yesterday
        # We need to access the DB object directly
        result = await session.execute(select(UserStreak).where(UserStreak.user_id == user_id))
        db_streak = result.scalar_one()
        db_streak.last_activity_date = date.today() - timedelta(days=1)
        await session.commit()
        
        # Consume again today
        await content_service.update_content_status(
            user_id, 
            content2.id, # Reuse content 2
            ContentStatusUpdate(status=ContentStatus.CONSUMED, time_spent_seconds=60)
        )
        await session.commit()

        streak = await streak_service.get_streak(str(user_id))
        print(f"   Current Streak: {streak.current_streak}")
        assert streak.current_streak == 2, f"Expected 2, got {streak.current_streak}"
        print("   ✅ Passed")

        # ---------------------------------------------------------
        # CASE 4: Broken Streak (Reset)
        # ---------------------------------------------------------
        print("\n📝 TEST 4: Broken Streak Simulation (Expect Streak -> 1)")
        # Manually set streak to 10 but last activity to 3 days ago
        result = await session.execute(select(UserStreak).where(UserStreak.user_id == user_id))
        db_streak = result.scalar_one()
        db_streak.current_streak = 10
        db_streak.last_activity_date = date.today() - timedelta(days=3)
        await session.commit()

        # Consume today
        await content_service.update_content_status(
            user_id, 
            content.id, # Reuse content 1
            ContentStatusUpdate(status=ContentStatus.CONSUMED, time_spent_seconds=60)
        )
        await session.commit()

        streak = await streak_service.get_streak(str(user_id))
        print(f"   Current Streak: {streak.current_streak}")
        assert streak.current_streak == 1, f"Expected 1 (Reset), got {streak.current_streak}"
        print("   ✅ Passed")

        # Cleanup
        print("\n🧹 Cleanup...")
        await session.execute(delete(UserProfile).where(UserProfile.user_id == user_id))
        await session.execute(delete(UserStreak).where(UserStreak.user_id == user_id))
        await session.execute(delete(UserContentStatus).where(UserContentStatus.user_id == user_id))
        await session.execute(delete(Content).where(Content.source_id == source.id))
        await session.execute(delete(Source).where(Source.id == source.id))
        await session.commit()
        print("   Done.")

if __name__ == "__main__":
    asyncio.run(verify_streak())
