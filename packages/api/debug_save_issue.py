import asyncio
from uuid import UUID
from sqlalchemy import select
from app.database import init_db, get_db
from app.models.content import Content, UserContentStatus
from app.models.user import UserProfile
from app.services.recommendation_service import RecommendationService
from app.services.content_service import ContentService

async def debug_save():
    await init_db()
    async for db in get_db():
        # 1. Get a user and a content
        user_stmt = select(UserProfile).limit(1)
        user_res = await db.execute(user_stmt)
        user = user_res.scalar_one_or_none()
        
        if not user:
             print("No user found!")
             return
             
        user_id = user.user_id
        
        # Grab first content
        content_stmt = select(Content).limit(1)
        content_res = await db.execute(content_stmt)
        content = content_res.scalar_one_or_none()
        
        if not content:
            print("No content found!")
            return

        print(f"Testing with User: {user_id}, Content: {content.id}")
        
        # 2. Save it
        svc = ContentService(db)
        await svc.set_save_status(user_id, content.id, True)
        await db.commit()
        print("Set is_saved = True")

        # 3. Check with RecommendationService
        rec_svc = RecommendationService(db)
        saved_feed = await rec_svc.get_feed(user_id, saved_only=True)
        
        print(f"Saved items count: {len(saved_feed)}")
        for item in saved_feed:
            print(f" - Saved Item: {item.id}, Title: {item.title}, is_saved: {getattr(item, 'is_saved', 'N/A')}")

if __name__ == "__main__":
    asyncio.run(debug_save())
