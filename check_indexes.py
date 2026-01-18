import asyncio
import os
import sys
from sqlalchemy import inspect
from sqlalchemy.ext.asyncio import create_async_engine

# Add parent directory to path to allow imports from app
sys.path.append(os.path.join(os.getcwd(), "packages/api"))
from app.database import DATABASE_URL

async def check_indexes():
    # Use sync engine for inspection as inspect() is synchronous
    from sqlalchemy import create_engine
    
    # fix protocol for sync engine
    sync_url = DATABASE_URL.replace("+asyncpg", "")
    engine = create_engine(sync_url)
    
    inspector = inspect(engine)
    indexes = inspector.get_indexes("contents")
    
    print("Indexes on 'contents':")
    for idx in indexes:
        print(f"- {idx['name']}: {idx['column_names']}")
        
    print("\nIndexes on 'user_content_status':")
    indexes_ucs = inspector.get_indexes("user_content_status")
    for idx in indexes_ucs:
        print(f"- {idx['name']}: {idx['column_names']}")

if __name__ == "__main__":
    from dotenv import load_dotenv
    from pathlib import Path
    load_dotenv(Path("packages/api/.env"))
    asyncio.run(check_indexes())
