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
        print("--- USERS FOLLOWING SOCIALTER ---")
        stmt = text("""
            SELECT u.user_id, u.display_name, s.name 
            FROM user_sources us 
            JOIN user_profiles u ON us.user_id = u.user_id 
            JOIN sources s ON us.source_id = s.id 
            WHERE s.name LIKE 'Socialter%'
        """)
        res = await conn.execute(stmt)
        for row in res:
            print(f"User: {row.user_id} ({row.display_name}) -> Source: {row.name}")
            
    await engine.dispose()

if __name__ == "__main__":
    asyncio.run(main())
