
import asyncio
import os
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine
from dotenv import load_dotenv

# Load .env from the current directory
load_dotenv()

async def check_connection():
    db_url = os.environ.get("DATABASE_URL")
    if not db_url:
        print("❌ DATABASE_URL not found in environment")
        return

    # Fix URL if needed (like in app/config.py)
    if db_url.startswith("postgres://"):
        db_url = db_url.replace("postgres://", "postgresql+asyncpg://", 1)
    elif db_url.startswith("postgresql://") and "+asyncpg" not in db_url:
        db_url = db_url.replace("postgresql://", "postgresql+asyncpg://", 1)

    print(f"🔍 Testing connection to: {db_url.split('@')[-1]}") # Hide credentials
    
    try:
        engine = create_async_engine(
            db_url, 
            connect_args={
                "command_timeout": 5,
            }
        )
        async with engine.begin() as conn:
            await conn.execute(text("SELECT 1"))
        print("✅ Connection successful!")
    except Exception as e:
        print(f"❌ Connection failed: {e}")

if __name__ == "__main__":
    asyncio.run(check_connection())
