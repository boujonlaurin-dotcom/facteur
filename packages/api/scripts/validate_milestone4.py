#!/usr/bin/env python3
"""Script de validation Milestone 4 - CRON Job.

Simule l'exécution du job Top 3 et vérifie la persistance en base.
"""
import asyncio
import sys
import uuid
import datetime
from sqlalchemy import select, delete

sys.path.insert(0, '.')

from app.database import async_session_maker
from app.models.user import UserProfile, UserInterest, UserPreference
from app.models.source import Source, UserSource
from app.models.enums import SourceType, ContentType
from app.models.content import Content
from app.models.daily_top3 import DailyTop3
from app.workers.top3_job import generate_daily_top3_job

async def main():
    print("=" * 50)
    print("MILESTONE 4 VALIDATION - Top 3 Job")
    print("=" * 50)
    
    async with async_session_maker() as session:
        # 1. Setup Test Data
        # A. Create User
        user_id = uuid.uuid4()
        print(f"Creating test user {user_id}...")
        
        profile = UserProfile(
            user_id=user_id,
            display_name="Test User Top3",
            onboarding_completed=True
        )
        session.add(profile)
        
        # B. Create Sources
        source1_id = uuid.uuid4()
        source2_id = uuid.uuid4()
        
        source1 = Source(
            id=source1_id,
            name="Source Une",
            url="http://example.com/1",
            feed_url="http://example.com/feed1",
            type=SourceType.ARTICLE,
            theme="tech",
            une_feed_url="http://example.com/une", # Simule une source Une
            is_curated=True
        )
        
        source2 = Source(
            id=source2_id,
            name="Source Followed",
            url="http://example.com/2",
            feed_url="http://example.com/feed2",
            type=SourceType.ARTICLE,
            theme="politics",
            is_curated=True
        )
        session.add_all([source1, source2])
        
        # C. User Follows Source 2
        user_source = UserSource(user_id=user_id, source_id=source2_id)
        session.add(user_source)
        
        # D. User Interests
        interest = UserInterest(user_id=user_id, interest_slug="tech", weight=1.0)
        session.add(interest)
        
        # E. Create Contents (Published recently)
        now = datetime.datetime.utcnow()
        
        c1 = Content(
            id=uuid.uuid4(),
            source_id=source1_id, # Une
            title="Article Une Important",
            url="http://example.com/c1",
            guid="guid-c1",
            published_at=now - datetime.timedelta(hours=2),
            content_type=ContentType.ARTICLE
        )
        
        c2 = Content(
            id=uuid.uuid4(),
            source_id=source2_id, # Followed
            title="Article Followed Source",
            url="http://example.com/c2",
            guid="guid-c2",
            published_at=now - datetime.timedelta(hours=3),
            content_type=ContentType.ARTICLE
        )
        
        c3 = Content(
            id=uuid.uuid4(),
            source_id=source1_id, 
            title="Article Other",
            url="http://example.com/c3",
            guid="guid-c3",
            published_at=now - datetime.timedelta(hours=4),
            content_type=ContentType.ARTICLE
        )
        
        session.add_all([c1, c2, c3])
        await session.commit()
        
        try:
            # 2. Run Job
            # On mock fetch_une_guids pour retourner le guid de c1
            import app.workers.top3_job
            
            async def mock_fetch_une_guids(sess):
                print("  [Mock] Returning Une GUIDs")
                return {"guid-c1"}
                
            app.workers.top3_job.fetch_une_guids = mock_fetch_une_guids
            
            print("Running generate_daily_top3_job()...")
            await generate_daily_top3_job(trigger_manual=True)
            
            # 3. Verify Results
            print("Verifying results in DB...")
            
            stmt = select(DailyTop3).where(DailyTop3.user_id == user_id).order_by(DailyTop3.rank)
            results = (await session.execute(stmt)).scalars().all()
            
            if not results:
                print("❌ FAILED: No DailyTop3 entries found for user")
                return 1
            
            print(f"✅ Found {len(results)} items in Top 3")
            
            for item in results:
                print(f"  - Rank {item.rank}: Content {item.content_id}, Reason: {item.top3_reason}")
            
            # Vérifications spécifiques
            has_une = any(i.top3_reason == "À la Une" for i in results)
            has_followed = any(i.top3_reason == "Source suivie" for i in results)
            
            if has_une:
                print("  ✅ 'À la Une' detected")
            else:
                print("  ⚠️ 'À la Une' NOT detected (Check scoring/boost)")
                
            if has_followed:
                print("  ✅ 'Source suivie' detected")
            else:
                print("  ⚠️ 'Source suivie' NOT detected (Check logic - might be Recommandé if not boosted)")

            # On valide si on a au moins 2 items (c1 et c2)
            if len(results) >= 2:
                print("✅ MILESTONE 4 VALIDATED - Job executed and persisted data")
                return 0
            else:
                print("❌ MILESTONE 4 FAILED - Not enough items generated")
                return 1

        except Exception as e:
            print(f"❌ ERROR: {e}")
            import traceback
            traceback.print_exc()
            return 1
            
        finally:
            # Cleanup
            print("Cleaning up test data...")
            await session.execute(delete(DailyTop3).where(DailyTop3.user_id == user_id))
            await session.execute(delete(UserSource).where(UserSource.user_id == user_id))
            await session.execute(delete(UserInterest).where(UserInterest.user_id == user_id))
            await session.execute(delete(UserProfile).where(UserProfile.user_id == user_id))
            await session.execute(delete(Content).where(Content.id.in_([c1.id, c2.id, c3.id])))
            await session.execute(delete(Source).where(Source.id.in_([source1_id, source2_id])))
            await session.commit()

if __name__ == "__main__":
    asyncio.run(main())
