"""Script pour ajouter la colonne une_feed_url manquante."""
from dotenv import load_dotenv
from pathlib import Path

load_dotenv(Path(__file__).parent.parent / ".env", override=True)

import asyncio
import os
import sys

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import text
from app.database import async_session_maker, init_db


async def add_missing_column():
    """Ajoute la colonne une_feed_url si elle n'existe pas."""
    await init_db()
    
    async with async_session_maker() as session:
        # Vérifier si la colonne existe
        check_sql = text("""
            SELECT column_name 
            FROM information_schema.columns 
            WHERE table_name = 'sources' AND column_name = 'une_feed_url'
        """)
        result = await session.execute(check_sql)
        exists = result.scalar_one_or_none()
        
        if exists:
            print("✓ Column 'une_feed_url' already exists")
        else:
            print("Adding column 'une_feed_url' to sources table...")
            add_sql = text("ALTER TABLE sources ADD COLUMN une_feed_url TEXT")
            await session.execute(add_sql)
            await session.commit()
            print("✓ Column 'une_feed_url' added successfully")


if __name__ == "__main__":
    asyncio.run(add_missing_column())
