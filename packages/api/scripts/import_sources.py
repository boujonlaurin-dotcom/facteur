import asyncio
import csv
import os
import re
import sys
from pathlib import Path
from typing import Optional, Dict, Any

import httpx
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from dotenv import load_dotenv

# Add parent directory to path to allow imports from app
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.models.source import Source
from app.models.enums import BiasOrigin, BiasStance, ReliabilityScore, SourceType

load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL")
# Correct path to project root
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
CSV_PATH = os.path.join(PROJECT_ROOT, "sources", "sources.csv")

TYPE_MAPPING = {
    "Site": "article",
    "Newsletter": "article",
    "RSS": "article",
    "Podcast": "podcast",
    "YouTube": "youtube"
}

THEME_MAPPING = {
    "Tech & Futur": "tech",
    "Géopolitique": "geopolitics",
    "Économie": "economy",
    "Société & Climat": "society_climate",
    "Culture & Idées": "culture_ideas"
}

# Specific fallbacks for the 24 curated sources if detection fails
CURATED_FEED_FALLBACKS = {
    "https://wondery.com/shows/guerres-de-business/": "https://feeds.megaphone.fm/WWS2399238883",
    "https://www.irsem.fr/le-collimateur.html": "https://feeds.audiomeans.fr/feed/7f9a1cb1-0490-4886-9f6e-2195f4c4a6a5",
    "https://www.slate.fr/podcasts/transfert": "https://feeds.audiomeans.fr/feed/295f7004-9442-4b26-8854-d4b8f5f24255",
    "https://www.arte.tv/fr/videos/RC-014036/le-dessous-des-cartes/": "https://www.youtube.com/feeds/videos.xml?channel_id=UC7sXGI8p8PvKosLWagkK9wQ", 
    "https://www.youtube.com/user/ScienceEtonnante": "https://www.youtube.com/feeds/videos.xml?channel_id=UC0NCBJ8G4BPaK9K-E86_m8A",
    "https://www.youtube.com/user/dirtybiology": "https://www.youtube.com/feeds/videos.xml?channel_id=UCtqICqGbPSbTN09K1_7VZ3Q",
    "https://www.youtube.com/user/monsieurbidouille": "https://www.youtube.com/feeds/videos.xml?user=monsieurbidouille",
    "https://www.youtube.com/channel/UCLXDAkJ3rTe0khbCV1Q7hSA": "https://www.youtube.com/feeds/videos.xml?channel_id=UCLXDNUOO3EQ80VmD9nQBHPg",
    "https://www.epsiloon.com/": None,  # No RSS feed available
    "https://www.philomag.com/": "https://www.philomag.com/feed",
    "https://nouveaudepart.co/": "https://nouveaudepart.substack.com/feed",
    "https://www.techtrash.fr/": "https://www.techtrash.fr/rss/",
    "https://le1hebdo.fr/": "https://le1hebdo.fr/rss.php",
    "https://theconversation.com/fr": "https://theconversation.com/fr/articles.atom",
    "https://www.socialter.fr/": "https://www.socialter.fr/rss",
    "https://www.alternatives-economiques.fr/": "https://www.alternatives-economiques.fr/flux-rss",
    "https://www.lefigaro.fr/": "https://www.lefigaro.fr/rss/figaro_actualites.xml",
    "https://www.lesechos.fr/": "https://services.lesechos.fr/rss/les-echos-une.xml",
    "https://www.lopinion.fr/": "https://www.lopinion.fr/index.rss",
    "https://www.lepoint.fr/": "https://www.lepoint.fr/rss.xml",
    "https://www.politico.eu/": "https://www.politico.eu/feed/",
    "https://www.commentaire.fr/": "https://www.commentaire.fr/rss"
}

async def detect_youtube_feed(url: str) -> Optional[str]:
    """Detect YouTube RSS feed URL from a channel URL."""
    if url in CURATED_FEED_FALLBACKS:
        return CURATED_FEED_FALLBACKS[url]

    channel_match = re.search(r"youtube\.com/channel/(UC[\w-]+)", url)
    if channel_match:
        channel_id = channel_match.group(1)
        return f"https://www.youtube.com/feeds/videos.xml?channel_id={channel_id}"
    
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            headers = {"User-Agent": "Mozilla/5.0"}
            response = await client.get(url, follow_redirects=True, headers=headers)
            if response.status_code == 200:
                id_match = re.search(r'"channelId":"(UC[\w-]+)"', response.text) or \
                           re.search(r'"externalId":"(UC[\w-]+)"', response.text)
                if id_match:
                    return f"https://www.youtube.com/feeds/videos.xml?channel_id={id_match.group(1)}"
    except:
        pass
    return None

async def detect_site_feed(url: str) -> Optional[str]:
    """Detect RSS feed for a website."""
    if url in CURATED_FEED_FALLBACKS:
        return CURATED_FEED_FALLBACKS[url]

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            headers = {"User-Agent": "Mozilla/5.0"}
            response = await client.get(url, follow_redirects=True, headers=headers)
            if response.status_code == 200:
                patterns = [
                    r'<link[^>]+type="application/rss\+xml"[^>]+href="([^"]+)"',
                    r'<link[^>]+type="application/atom\+xml"[^>]+href="([^"]+)"'
                ]
                for pattern in patterns:
                    match = re.search(pattern, response.text)
                    if match:
                        feed_url = match.group(1)
                        if not feed_url.startswith("http"):
                            from urllib.parse import urljoin
                            feed_url = urljoin(url, feed_url)
                        return feed_url
    except:
        pass
    return None

async def process_source(source_data: Dict[str, str], session: AsyncSession):
    name = source_data.get("Name")
    url = source_data.get("URL")
    csv_type = source_data.get("Type")
    csv_theme = source_data.get("Thème")
    rationale = source_data.get("Rationale")
    csv_bias = source_data.get("Bias", "unknown")
    csv_reliability = source_data.get("Reliability", "unknown")
    
    internal_type = TYPE_MAPPING.get(csv_type, "article")
    internal_theme = THEME_MAPPING.get(csv_theme, "other")
    
    # Map bias string to enum value (handling hyphens etc)
    bias_val = csv_bias.lower()
    reliability_val = csv_reliability.lower()
    
    # Heuristic mapping for FQS pillars (Story 7.5)
    score_indep = None
    score_rigor = None
    score_ux = None
    
    if reliability_val == "high":
        score_indep, score_rigor, score_ux = 0.9, 0.9, 0.8
    elif reliability_val in ["medium", "mixed"]:
        score_indep, score_rigor, score_ux = 0.6, 0.6, 0.6
    elif reliability_val == "low":
        score_indep, score_rigor, score_ux = 0.3, 0.3, 0.4

    feed_url = None
    if internal_type == "youtube":
        feed_url = await detect_youtube_feed(url)
    elif internal_type == "podcast" and "radiofrance.fr" in url:
        feed_url = f"{url.rstrip('/')}.rss"
    else:
        feed_url = await detect_site_feed(url)
        
    if not feed_url:
        print(f"⚠️ Warning: No feed found for {name} ({url}). Skipping.")
        return

    # Generate logo URL
    from urllib.parse import urlparse
    domain = urlparse(url).netloc
    logo_url = f"https://www.google.com/s2/favicons?domain={domain}&sz=128"

    result = await session.execute(select(Source).where(Source.feed_url == feed_url))
    existing_source = result.scalars().first()
    
    if existing_source:
        existing_source.name = name
        existing_source.url = url
        existing_source.type = SourceType(internal_type)
        existing_source.theme = internal_theme
        existing_source.description = rationale
        existing_source.logo_url = logo_url
        existing_source.bias_stance = BiasStance(bias_val)
        existing_source.reliability_score = ReliabilityScore(reliability_val)
        existing_source.bias_origin = BiasOrigin.CURATED
        existing_source.score_independence = score_indep
        existing_source.score_rigor = score_rigor
        existing_source.score_ux = score_ux
    else:
        new_source = Source(
            name=name, url=url, feed_url=feed_url,
            type=SourceType(internal_type), theme=internal_theme,
            description=rationale, logo_url=logo_url,
            is_curated=True, is_active=True,
            bias_stance=BiasStance(bias_val),
            reliability_score=ReliabilityScore(reliability_val),
            bias_origin=BiasOrigin.CURATED,
            score_independence=score_indep,
            score_rigor=score_rigor,
            score_ux=score_ux
        )
        session.add(new_source)

async def main():
    if not DATABASE_URL or not os.path.exists(CSV_PATH):
        return

    engine = create_async_engine(DATABASE_URL)
    AsyncSessionLocal = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    async with AsyncSessionLocal() as session:
        async with session.begin():
            with open(CSV_PATH, mode='r', encoding='utf-8') as csvfile:
                reader = csv.DictReader(csvfile)
                for row in reader:
                    await process_source(row, session)
        await session.commit()
    await engine.dispose()

if __name__ == "__main__":
    asyncio.run(main())
