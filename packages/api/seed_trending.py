"""Seed trending data: check user_sources for a given user and populate if empty.

Usage:
  cd packages/api && source venv/bin/activate
  python seed_trending.py

Requires DATABASE_URL env var (or .env file) pointing to Supabase.
"""
import asyncio
from uuid import UUID

from sqlalchemy import select, func, text
from app.database import AsyncSessionLocal
from app.models.source import Source, UserSource


async def main():
    async with AsyncSessionLocal() as db:
        # 1. Find user boujon.laurin@gmail.com via auth.users (Supabase)
        try:
            result = await db.execute(
                text("SELECT id FROM auth.users WHERE email = 'boujon.laurin@gmail.com' LIMIT 1")
            )
            row = result.first()
            if not row:
                print("User boujon.laurin@gmail.com not found in auth.users")
                return
            user_id = row[0]
            print(f"Found user: {user_id}")
        except Exception as e:
            print(f"Cannot query auth.users (maybe local dev?): {e}")
            print("Set user_id manually below and re-run.")
            return

        # 2. Check existing user_sources
        us_count = await db.scalar(
            select(func.count()).select_from(UserSource).where(UserSource.user_id == user_id)
        )
        print(f"Existing user_sources for this user: {us_count}")

        # 3. Check total sources in DB
        src_count = await db.scalar(
            select(func.count()).select_from(Source).where(Source.is_active == True)
        )
        print(f"Total active sources in DB: {src_count}")

        # 4. If user has sources, trending should work - show what it would return
        if us_count and us_count > 0:
            trending_q = (
                select(Source.name, func.count(UserSource.user_id).label("cnt"))
                .join(UserSource)
                .where(Source.is_active == True)
                .group_by(Source.id)
                .order_by(func.count(UserSource.user_id).desc())
                .limit(10)
            )
            result = await db.execute(trending_q)
            rows = result.all()
            print(f"\nTrending sources ({len(rows)}):")
            for name, cnt in rows:
                print(f"  {cnt}x {name}")
            return

        # 5. No user_sources - seed from curated sources
        print("\nNo user_sources found. Seeding from curated sources...")
        curated = await db.execute(
            select(Source).where(Source.is_curated == True, Source.is_active == True)
        )
        curated_sources = curated.scalars().all()
        print(f"Found {len(curated_sources)} curated sources to seed")

        from uuid import uuid4
        for src in curated_sources:
            existing = await db.scalar(
                select(UserSource).where(
                    UserSource.user_id == user_id,
                    UserSource.source_id == src.id,
                )
            )
            if not existing:
                us = UserSource(
                    id=uuid4(),
                    user_id=user_id,
                    source_id=src.id,
                    is_custom=False,
                )
                db.add(us)
                print(f"  + {src.name}")

        await db.commit()
        print("\nDone! Trending should now show these sources.")


if __name__ == "__main__":
    asyncio.run(main())
