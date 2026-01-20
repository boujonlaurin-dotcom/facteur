"""
Script to list all unique themes found in the Source table.
"""
import asyncio
import sys
import os
from sqlalchemy import select, func

# Setup path
sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from app.config import get_settings
from app.models.source import Source
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

async def inspect():
    print("--- INSPECTING SOURCE THEMES ---")
    settings = get_settings()
    engine = create_async_engine(settings.database_url, echo=False)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    
    async with async_session() as session:
        result = await session.execute(select(Source.theme).distinct())
        themes = result.scalars().all()
        
        with open("themes_dump_py.txt", "w") as f:
            f.write(f"Found {len(themes)} distinct themes:\n")
            for t in themes:
                f.write(f"   '{t}'\n")
                print(f"   '{t}'")
            
    print("--- END ---")

if __name__ == "__main__":
    asyncio.run(inspect())
