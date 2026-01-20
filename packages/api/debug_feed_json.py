
import asyncio
import os
import sys
from fastapi.testclient import TestClient
from app.main import app
from app.dependencies import get_current_user_id

# Valid User ID from previous logs (confirmed user)
TARGET_EMAIL = "boujon.laurin@gmail.com"

async def mock_get_current_user_id():
    from app.database import async_session_maker
    from sqlalchemy import text
    async with async_session_maker() as session:
        result = await session.execute(
            text("SELECT id FROM auth.users WHERE email = :email"),
            {"email": TARGET_EMAIL}
        )
        row = result.fetchone()
        if row:
            return str(row[0])
    return "00000000-0000-0000-0000-000000000000"

app.dependency_overrides[get_current_user_id] = mock_get_current_user_id

client = TestClient(app)

def main():
    print("------- FETCHING FEED JSON -------")
    try:
        response = client.get("/api/feed/?page=1&per_page=2")
        print(f"Status: {response.status_code}")
        if response.status_code == 200:
            import json
            print(json.dumps(response.json(), indent=2))
        else:
            print(response.text)
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    main()
