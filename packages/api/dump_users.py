import asyncio
import os
import sys

sys.path.append(os.getcwd())

from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

from app.config import get_settings

async def main():
    settings = get_settings()
    engine = create_async_engine(settings.database_url)
    
    async with engine.connect() as conn:
        print("--- USERS ---")
        res = await conn.execute(text("SELECT user_id, display_name FROM user_profiles"))
        users = res.all()
        for u in users:
            print(f"User: {u.user_id} ({u.display_name})")
            
            print("  Followed Sources:")
            followed = await conn.execute(text(f"SELECT s.name FROM user_sources us JOIN sources s ON us.source_id = s.id WHERE us.user_id = '{u.user_id}'"))
            for f in followed:
                print(f"    - {f.name}")
                
            print("  Interests:")
            interests = await conn.execute(text(f"SELECT interest_slug FROM user_interests WHERE user_id = '{u.user_id}'"))
            for i in interests:
                print(f"    - {i.interest_slug}")
            print("-" * 20)

    await engine.dispose()

if __name__ == "__main__":
    asyncio.run(main())
