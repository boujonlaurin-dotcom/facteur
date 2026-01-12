"""Test the perspectives API endpoint."""

import asyncio
import httpx
import os
from dotenv import load_dotenv

load_dotenv()


async def test_api():
    # Get a real content ID from DB first
    from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
    from sqlalchemy.orm import sessionmaker
    from sqlalchemy import select
    import sys
    sys.path.append(os.path.dirname(os.path.abspath(__file__)))
    
    from app.models.content import Content
    
    engine = create_async_engine(os.getenv("DATABASE_URL"))
    Session = sessionmaker(engine, class_=AsyncSession)
    
    async with Session() as session:
        result = await session.execute(
            select(Content.id, Content.title)
            .where(Content.content_type == "article")
            .limit(1)
        )
        content_id, title = result.first()
        print(f"📰 Testing with: {title[:60]}...")
        print(f"🔑 Content ID: {content_id}")
    
    await engine.dispose()
    
    # Now test the API by calling the service directly (bypass auth)
    from app.services.perspective_service import PerspectiveService
    
    service = PerspectiveService()
    keywords = service.extract_keywords(title)
    print(f"🔍 Keywords: {keywords}")
    
    import time
    start = time.time()
    perspectives = await service.search_perspectives(keywords)
    elapsed = time.time() - start
    
    print(f"⏱️  Latency: {elapsed*1000:.0f}ms")
    print(f"📊 Found {len(perspectives)} perspectives:")
    
    for p in perspectives:
        emoji = {"left": "🔴", "center-left": "🟠", "center": "🟣", 
                 "center-right": "🔵", "right": "🔷"}.get(p.bias_stance, "⚪")
        print(f"  {emoji} [{p.bias_stance:^12}] {p.source_name}: {p.title[:45]}...")


if __name__ == "__main__":
    asyncio.run(test_api())
