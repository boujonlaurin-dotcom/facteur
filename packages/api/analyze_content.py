"""Test to understand why clustering rate is low."""

import asyncio
import os
import sys
from collections import Counter
from dotenv import load_dotenv
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker, selectinload

sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from app.models.content import Content
from app.models.source import Source
from app.services.story_service import StoryService
from sqlalchemy import select, text
import re

load_dotenv()
DATABASE_URL = os.getenv("DATABASE_URL")

FRENCH_STOPWORDS = {
    "le", "la", "les", "un", "une", "des", "de", "du", "d", "l", "et", "en", "à", "au", "aux",
    "ce", "cette", "ces", "mon", "ma", "mes", "ton", "ta", "tes", "son", "sa", "ses",
    "notre", "nos", "votre", "vos", "leur", "leurs", "qui", "que", "quoi", "dont", "où",
    "se", "ne", "pas", "plus", "moins", "très", "bien", "mal", "tout", "tous", "toute", "toutes",
    "il", "elle", "on", "nous", "vous", "ils", "elles", "je", "tu", "me", "te", "lui",
    "y", "avec", "pour", "par", "sur", "sous", "dans", "entre", "vers", "chez", "sans",
    "est", "sont", "être", "avoir", "fait", "faire", "a", "ont", "peut", "été", "sera",
    "mais", "ou", "donc", "ni", "car", "si", "alors", "quand", "comme", "après", "avant",
    "encore", "aussi", "même", "autre", "autres", "peu", "beaucoup", "trop", "assez",
}

def extract_keywords(title):
    title_clean = title.lower()
    title_clean = re.sub(r'[^\w\s]', ' ', title_clean)
    words = title_clean.split()
    keywords = {w for w in words if len(w) > 3 and w not in FRENCH_STOPWORDS and not w.isdigit()}
    return keywords


async def analyze_content():
    engine = create_async_engine(DATABASE_URL)
    AsyncSessionLocal = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    
    async with AsyncSessionLocal() as session:
        result = await session.execute(
            select(Content).options(selectinload(Content.source))
            .where(Content.content_type == "article")
        )
        articles = result.scalars().all()
        
        print(f"📊 Analyzing {len(articles)} articles\n")
        
        # Analyze by source
        by_source = {}
        for a in articles:
            src = a.source.name if a.source else "Unknown"
            by_source.setdefault(src, []).append(a)
        
        print("📰 Articles per source:")
        for src, arts in sorted(by_source.items(), key=lambda x: -len(x[1])):
            print(f"  {src}: {len(arts)}")
        
        print("\n" + "=" * 60)
        
        # Analyze keyword frequency
        all_keywords = []
        for a in articles:
            all_keywords.extend(extract_keywords(a.title))
        
        keyword_freq = Counter(all_keywords)
        print("\n🔤 Most common keywords:")
        for kw, count in keyword_freq.most_common(30):
            print(f"  {kw}: {count}")
        
        # Find potential clusters
        print("\n" + "=" * 60)
        print("\n🔍 Potential clusters (articles sharing keywords):")
        
        keyword_to_articles = {}
        for a in articles:
            for kw in extract_keywords(a.title):
                keyword_to_articles.setdefault(kw, []).append(a)
        
        # Find keywords that appear in 2+ articles from different sources
        potential_clusters = []
        for kw, arts in keyword_to_articles.items():
            if len(arts) >= 2:
                sources = set(a.source.name for a in arts if a.source)
                if len(sources) >= 2:  # From different sources
                    potential_clusters.append((kw, arts, sources))
        
        potential_clusters.sort(key=lambda x: -len(x[1]))
        
        print(f"\nFound {len(potential_clusters)} keywords shared across sources:")
        for kw, arts, sources in potential_clusters[:15]:
            print(f"\n  '{kw}' ({len(arts)} articles from {len(sources)} sources):")
            for a in arts[:3]:
                src = a.source.name[:20] if a.source else "?"
                print(f"    [{src:20}] {a.title[:50]}...")
    
    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(analyze_content())
