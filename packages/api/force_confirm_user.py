import asyncio
import os
import sys
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

# Add current dir to sys path to import app.config
sys.path.append(os.getcwd())
from app.config import get_settings

async def force_confirm(email: str):
    settings = get_settings()
    # We use the database_url which usually has enough permissions to touch auth schema if it's the 'postgres' user
    engine = create_async_engine(settings.database_url)
    
    async with engine.connect() as conn:
        print(f"🔍 Searching for user with email: {email}")
        # Search in auth.users
        res = await conn.execute(text("SELECT id, email_confirmed_at FROM auth.users WHERE email = :email"), {"email": email})
        user = res.fetchone()
        
        if not user:
            print(f"❌ User '{email}' not found in auth.users table.")
            return

        user_id, confirmed_at = user
        if confirmed_at:
            print(f"✅ User '{email}' is ALREADY confirmed (at {confirmed_at}).")
        else:
            print(f"⏳ User '{email}' (ID: {user_id}) is NOT confirmed. Forcing confirmation...")
            await conn.execute(
                text("UPDATE auth.users SET email_confirmed_at = NOW(), updated_at = NOW() WHERE id = :user_id"),
                {"user_id": user_id}
            )
            await conn.commit()
            print(f"🚀 User '{email}' has been MANUALLY CONFIRMED.")
            
    await engine.dispose()

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python force_confirm_user.py <email>")
        sys.exit(1)
        
    target_email = sys.argv[1]
    asyncio.run(force_confirm(target_email))
