
import asyncio
import os
import sys
from dotenv import load_dotenv
from sqlalchemy import select, func

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
load_dotenv()

from app.database import async_session_maker
from app.services.sync_service import SyncService
from app.models.content import Content
from app.models.source import Source

async def test_sync():
    """Teste la synchronisation RSS manuellement."""
    print("🚀 Starting manual sync test...")
    
    async with async_session_maker() as session:
        # 1. Count before
        count_before = await session.scalar(select(func.count()).select_from(Content))
        print(f"📊 Contents before: {count_before}")
        
        # 2. Sync
        service = SyncService(session)
        try:
            results = await service.sync_all_sources()
            print(f"✅ Sync results: {results}")
        except Exception as e:
            print(f"❌ Error during sync: {e}")
            import traceback
            traceback.print_exc()
        finally:
            await service.close()
            
        # 3. Count after
        count_after = await session.scalar(select(func.count()).select_from(Content))
        print(f"📊 Contents after: {count_after}")
        print(f"📈 New contents: {count_after - count_before}")
        
        # 4. Verify distribution
        print("\nDistribution by type:")
        # Simple count per type query would be better but keeping it simple
        result = await session.execute(select(Content.content_type, func.count(Content.id)).group_by(Content.content_type))
        for type_, count in result.all():
            print(f"  - {type_}: {count}")

if __name__ == "__main__":
    asyncio.run(test_sync())
