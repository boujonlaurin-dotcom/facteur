import asyncio
import os
import sys

sys.path.append(os.getcwd())

from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine
from app.config import get_settings
from app.services.sync_service import SyncService
from unittest.mock import MagicMock

async def main():
    settings = get_settings()
    engine = create_async_engine(settings.database_url)
    service = SyncService(MagicMock())
    
    async with engine.begin() as conn:
        print("REPAIR: Fetching contents with focus.courrierinternational.com or wordpress-like thumbnails")
        res = await conn.execute(text("""
            SELECT id, thumbnail_url 
            FROM contents 
            WHERE (thumbnail_url LIKE '%focus.courrierinternational.com%' AND thumbnail_url LIKE '%/644/%')
            OR thumbnail_url ~ '-[0-9]+x[0-9]+\.(jpg|jpeg|png)$'
        """))
        
        rows = res.all()
        print(f"Found {len(rows)} thumbnails to optimize.")
        
        for row in rows:
            optimized = service._optimize_thumbnail_url(row.thumbnail_url)
            if optimized != row.thumbnail_url:
                await conn.execute(text("UPDATE contents SET thumbnail_url = :url WHERE id = :id"), {"url": optimized, "id": row.id})
                print(f"Updated: {row.id}")

    await engine.dispose()
    print("REPAIR COMPLETE")

if __name__ == "__main__":
    asyncio.run(main())
