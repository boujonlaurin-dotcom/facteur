from app.models.content import Content
from app.models.user import UserSubtopic
from app.database import get_session
import asyncio
from sqlalchemy import select, text

async def test_models():
    print("Starting Model Test...")
    async with get_session() as session:
        # Simple select pour voir si ça répond
        print("Testing basic DB connection...")
        try:
            result = await session.execute(text("SELECT 1"))
            print("DB OK:", result.scalar())
        except Exception as e:
            print(f"DB FAIL: {e}")
            return
        
        # Test Content.topics
        print("Testing Content.topics access...")
        try:
            # We select just the column to see if it exists
            result = await session.execute(select(Content.id, Content.topics).limit(1))
            print("Content.topics OK")
        except Exception as e:
            print(f"Content.topics FAIL: {e}")
        
        # Test UserSubtopic
        print("Testing UserSubtopic access...")
        try:
            result = await session.execute(select(UserSubtopic).limit(1))
            print("UserSubtopic OK")
        except Exception as e:
            print(f"UserSubtopic FAIL: {e}")

if __name__ == "__main__":
    asyncio.run(test_models())
