import asyncio
import os
import sys

# Ajouter le dossier parent au path pour importer app
sys.path.append(os.getcwd())

# Configuration explicite
if "DATABASE_URL" not in os.environ:
    from dotenv import load_dotenv
    load_dotenv()

from sqlalchemy import select, func, or_, and_, text
from app.database import async_session_maker
from app.models.content import Content
from app.models.source import Source
from app.models.enums import ContentType

async def analyze_deep_dive():
    print("🚀 Starting Deep Dive analysis...")
    
    async with async_session_maker() as session:
        try:
            # 1. Total content
            result = await session.execute(select(func.count(Content.id)))
            total = result.scalar()
            print(f"Total contents: {total}")

            # 2. Check matching logic used in service
            query = (
                select(Content.title, Content.content_type, Content.published_at, Source.name)
                .join(Content.source)
                .where(
                    or_(
                        and_(
                            or_(Content.duration_seconds > 600, Content.duration_seconds == None),
                            Content.content_type.in_([ContentType.PODCAST, ContentType.YOUTUBE])
                        ),
                        and_(
                            Content.content_type == ContentType.ARTICLE,
                            func.length(Content.description) > 2000
                        )
                    )
                )
                .order_by(Content.published_at.desc())
            )
            result = await session.execute(query)
            matches = result.all()
            print(f"\nTotal Deep Dive Matches in DB: {len(matches)}")
            
            if len(matches) > 0:
                print("\nMost recent matches:")
                for m in matches[:10]:
                    print(f"- {m[2].strftime('%Y-%m-%d')} | [{m[1]}] {m[0]} ({m[3]})")
                
                # Check how many are from the last 7 days
                from datetime import datetime, timedelta
                seven_days_ago = datetime.utcnow() - timedelta(days=7)
                recent_count = sum(1 for m in matches if m[2] > seven_days_ago)
                print(f"\nMatches from last 7 days: {recent_count}")

            # Check themes
            query = select(Source.theme, func.count(Content.id)).join(Content.source).group_by(Source.theme)
            result = await session.execute(query)
            themes = result.all()
            print("\nContent counts by theme:")
            for theme, count in themes:
                print(f"- {theme}: {count}")

        except Exception as e:
            print(f"❌ Error during analysis: {e}")
            import traceback
            traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(analyze_deep_dive())
