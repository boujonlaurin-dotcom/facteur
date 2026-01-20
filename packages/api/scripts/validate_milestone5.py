#!/usr/bin/env python3
"""Script de validation Milestone 5 - API Endpoints.

Vérifie l'API GET /api/feed (structure Briefing) et POST /briefing/read.
"""
import asyncio
import sys
import uuid
import datetime
import os

# Ensure clean imports
sys.path.insert(0, '.')

# Setup Test Client
from fastapi.testclient import TestClient
from app.main import app
from app.database import get_db, async_session_maker
from app.models.user import UserProfile
from app.models.content import Content
from app.models.source import Source
from app.models.daily_top3 import DailyTop3
from app.models.enums import SourceType, ContentType
from app.dependencies import get_current_user_id

# Mock auth dependency
user_id = uuid.uuid4()
print(f"Test User ID: {user_id}")

def override_get_current_user_id():
    return str(user_id)

app.dependency_overrides[get_current_user_id] = override_get_current_user_id

client = TestClient(app)

async def setup_data():
    async with async_session_maker() as session:
        # User
        profile = UserProfile(user_id=user_id, display_name="API User", onboarding_completed=True)
        session.add(profile)
        
        # Source
        src = Source(
            id=uuid.uuid4(), name="API Source", url="http://api.test", feed_url="http://api.test/rss", 
            type=SourceType.ARTICLE, is_curated=True
        )
        session.add(src)
        
        # Content
        c1 = Content(
            id=uuid.uuid4(), source_id=src.id, title="Briefing Item 1", url="http://c1", 
            guid="c1", published_at=datetime.datetime.utcnow(), content_type=ContentType.ARTICLE
        )
        session.add(c1)
        
        # DailyTop3 Item
        top3 = DailyTop3(
            user_id=user_id, content_id=c1.id, rank=1, top3_reason="Test Reason", 
            generated_at=datetime.datetime.utcnow(), consumed=False
        )
        session.add(top3)
        await session.commit()
        return str(c1.id)

async def verify_db_consumed(content_id):
    async with async_session_maker() as session:
        from sqlalchemy import select
        stmt = select(DailyTop3).where(
            DailyTop3.user_id == user_id, 
            DailyTop3.content_id == uuid.UUID(content_id)
        )
        res = (await session.execute(stmt)).scalar_one()
        return res.consumed

async def cleanup():
    async with async_session_maker() as session:
        from sqlalchemy import delete
        await session.execute(delete(DailyTop3).where(DailyTop3.user_id == user_id))
        await session.execute(delete(UserProfile).where(UserProfile.user_id == user_id))
        await session.execute(delete(Content).where(Content.title == "Briefing Item 1"))
        await session.execute(delete(Source).where(Source.name == "API Source"))
        await session.commit()

def run_tests():
    print("="*50)
    print("MILESTONE 5 VALIDATION - API")
    print("="*50)
    
    # 1. Setup
    print("Setting up data...")
    try:
        content_id = asyncio.run(setup_data())
    except Exception as e:
        print(f"Setup Failed: {e}")
        return 1

    try:
        # 2. Test GET /api/feed
        print("Testing GET /api/feed...")
        response = client.get("/api/feed/?limit=10")
        
        if response.status_code != 200:
            print(f"❌ FAILED: Status {response.status_code}")
            print(response.text)
            return 1
            
        data = response.json()
        
        # Structure Check
        if "briefing" not in data or "items" not in data:
            print("❌ FAILED: Missing 'briefing' or 'items' keys")
            print(data.keys())
            return 1
        
        briefing = data["briefing"]
        print(f"Briefing items found: {len(briefing)}")
        
        if len(briefing) != 1:
            print("❌ FAILED: Expected 1 briefing item")
            return 1
            
        item = briefing[0]
        if item["reason"] != "Test Reason" or item["rank"] != 1:
            print(f"❌ FAILED: Data mismatch: {item}")
            return 1
            
        print("✅ GET /api/feed validated")

        # 3. Test POST /api/feed/briefing/{id}/read
        print(f"Testing POST /api/feed/briefing/{content_id}/read...")
        
        read_resp = client.post(f"/api/feed/briefing/{content_id}/read")
        
        if read_resp.status_code != 200:
            print(f"❌ FAILED: Status {read_resp.status_code}")
            return 1
            
        print("✅ POST verified (API side)")
        
        # 4. Verify DB persistence
        is_consumed = asyncio.run(verify_db_consumed(content_id))
        if is_consumed:
            print("✅ DB Verification: Item marked as consumed")
        else:
            print("❌ FAILED: DB says is_consumed=False")
            return 1

        print("✅ MILESTONE 5 VALIDATED")
        return 0
        
    finally:
        print("Cleaning up...")
        asyncio.run(cleanup())

if __name__ == "__main__":
    sys.exit(run_tests())
