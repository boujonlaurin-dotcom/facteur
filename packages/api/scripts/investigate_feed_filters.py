import asyncio
import datetime
import sys
import os

# Create a minimal context to run DB queries
sys.path.append(os.path.join(os.getcwd(), "packages/api"))

from sqlalchemy import select, func, text
from app.database import async_session_maker
from app.models.source import Source
from app.models.content import Content
from app.services.recommendation_service import SERENE_FILTER_KEYWORDS
import re

async def main():
    async with async_session_maker() as session:
        print("--- Investigating 'Dernières news' (Breaking) ---")
        
        # Check Source Themes
        themes = await session.execute(select(Source.theme, func.count(Source.id)).group_by(Source.theme))
        print("\nSource Themes distribution:")
        for theme, count in themes:
            print(f"  {theme}: {count} sources")
            
        # Check Recent Content Volume for Hard News
        hard_news_themes = ['society_climate', 'geopolitics', 'economy']
        now = datetime.datetime.utcnow()
        
        windows = [12, 24, 48, 72]
        for hours in windows:
            limit_date = now - datetime.timedelta(hours=hours)
            stmt = (
                select(func.count(Content.id))
                .join(Source)
                .where(Content.published_at >= limit_date)
                .where(Source.theme.in_(hard_news_themes))
            )
            count = await session.scalar(stmt)
            print(f"  Articles in hard news themes in last {hours}h: {count}")

        print("\n--- Investigating 'Rester serein' (Serene) ---")
        print("\nCurrent Keywords:", SERENE_FILTER_KEYWORDS)
        
        test_titles = [
            "Manifestation à Paris",
            "Les manifestations continuent",
            "En Indonésie, le trafic de bébés prospère",
            "Chaleurs extrêmes : la moitié de l'humanité concernée",
            "Mort d'un célèbre acteur",
            "Attentat déjoué",
            "Crise au Venezuela",
            "Fonte des glaces au Groenland"
        ]
        
        pattern = '|'.join(SERENE_FILTER_KEYWORDS)
        regex = re.compile(pattern, re.IGNORECASE)
        
        print("\nTesting Regex against examples:")
        for title in test_titles:
            match = regex.search(title)
            status = "BLOCKED" if match else "ALLOWED"
            print(f"  '{title}' -> {status} (Match: {match.group(0) if match else 'None'})")

if __name__ == "__main__":
    asyncio.run(main())
