
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
    print("------- FETCHING SOURCES CATALOG -------")
    try:
        # Testing specific endpoint used by mobile app
        response = client.get("/api/sources/catalog") 
        print(f"Status: {response.status_code}")
        if response.status_code == 200:
            print("✅ Success! Response preview:")
            import json
            data = response.json()
            if isinstance(data, list):
                print(f"Is List: Yes. Count: {len(data)}")
                if len(data) > 0:
                    print("First item:", json.dumps(data[0], indent=2))
            else:
                print(f"❌ EXPECTED LIST, GOT {type(data)}")
                print(json.dumps(data, indent=2))
        else:
            print(f"❌ Error {response.status_code}:")
            print(response.text)
    except Exception as e:
        print(f"💥 Exception: {e}")

if __name__ == "__main__":
    main()
