from dotenv import load_dotenv
from pathlib import Path

# Load .env from packages/api relative to this script, override existing env vars
# MUST be done before any imports from 'app' to ensure settings aren't pre-loaded
load_dotenv(Path(__file__).parent.parent / ".env", override=True)

import asyncio
import csv
import json
import os
import re
import sys
from typing import Optional, Dict, Any, List

import httpx
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

# Add parent directory to path to allow imports from app
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.models.source import Source
from app.models.enums import BiasOrigin, BiasStance, ReliabilityScore, SourceType


DATABASE_URL = os.getenv("DATABASE_URL")

if DATABASE_URL:
    DATABASE_URL = DATABASE_URL.strip()
    # Normalize to postgresql+asyncpg://
    if DATABASE_URL.startswith("postgres://"):
        DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql+asyncpg://", 1)
    elif DATABASE_URL.startswith("postgresql://") and "+asyncpg" not in DATABASE_URL:
        DATABASE_URL = DATABASE_URL.replace("postgresql://", "postgresql+asyncpg://", 1)

# Correct path to project root
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
CSV_PATH = os.path.join(PROJECT_ROOT, "sources", "sources_master.csv")


TYPE_MAPPING = {
    "Site": "article",
    "Newsletter": "article",
    "RSS": "article",
    "Podcast": "podcast",
    "YouTube": "youtube"
}

# PRD Taxonomy Slugs
VALID_THEMES = {
    "tech", "society", "environment", "economy", "politics", 
    "culture", "science", "international"
}

# Curated feed fallbacks for sources where automatic detection fails
CURATED_FEED_FALLBACKS = {
    # --- New CURATED sources (Story 4.1c Part 2/3) ---
    "https://www.francetvinfo.fr/": "https://www.francetvinfo.fr/titres.rss",
    "https://www.radiofrance.fr/franceinter": "https://radiofrance-podcast.net/podcast09/rss_21207.xml",
    "https://www.rtl.fr/": "https://www.rtl.fr/actu/rss.xml",
    "https://www.europe1.fr/": "https://www.europe1.fr/rss.xml",
    "https://www.brut.media/fr": "https://www.brut.media/fr/flux-rss",
    "https://www.blast-info.fr/": "https://api.blast-info.fr/rss.xml",
    "https://bonpote.com/": "https://bonpote.com/feed/",
    # --- Indexed Tech sources fallbacks ---
    "https://www.frandroid.com/": "https://www.frandroid.com/feed",
    "https://www.numerama.com/": "https://www.numerama.com/feed/",
    "https://www.futura-sciences.com/": "https://www.futura-sciences.com/rss/actualites.xml",
    # --- Existing podcast fallbacks ---
    "https://wondery.com/shows/guerres-de-business/": "https://feeds.megaphone.fm/WWS2399238883",
    "https://www.irsem.fr/le-collimateur.html": "https://feeds.audiomeans.fr/feed/64ee3763-1a46-44c2-8640-3a69405a3ad8.xml",
    "https://www.slate.fr/podcasts/transfert": "https://feeds.360.audion.fm/EZqjvOzZXgWIKWg0EETBQ",
    "https://www.arte.tv/fr/videos/RC-014036/le-dessous-des-cartes/": "https://www.youtube.com/feeds/videos.xml?channel_id=UCHGMBrXUzClgjEzBMei-Jdw", 
    "https://www.youtube.com/user/ScienceEtonnante": "https://www.youtube.com/feeds/videos.xml?channel_id=UCaNlbnghtwlsGF-KzAFThqA",
    "https://www.youtube.com/user/dirtybiology": "https://www.youtube.com/feeds/videos.xml?channel_id=UCtqICqGbPSbTN09K1_7VZ3Q",
    "https://www.youtube.com/user/monsieurbidouille": "https://www.youtube.com/feeds/videos.xml?user=monsieurbidouille",
    "https://www.youtube.com/channel/UCLXDAkJ3rTe0khbCV1Q7hSA": "https://www.youtube.com/feeds/videos.xml?channel_id=UCLXDNUOO3EQ80VmD9nQBHPg",
    # Heu?reka YouTube channel
    "https://www.youtube.com/channel/UC7sXGI8p8PvKosLWagkK9wQ": "https://www.youtube.com/feeds/videos.xml?channel_id=UC7sXGI8p8PvKosLWagkK9wQ",
    "https://www.epsiloon.com/": None,  # No RSS feed available
    "https://www.philomag.com/": "https://www.philomag.com/feed",
    "https://nouveaudepart.co/": "https://nouveaudepart.substack.com/feed",
    "https://www.techtrash.fr/": None,  # Newsletter only, no RSS available
    "https://le1hebdo.fr/": None,  # No RSS available
    "https://theconversation.com/fr": "https://theconversation.com/fr/articles.atom",
    "https://www.socialter.fr/": "https://www.socialter.fr/rss",
    "https://www.alternatives-economiques.fr/": "https://www.alternatives-economiques.fr/flux-rss",
    "https://www.lefigaro.fr/": "https://www.lefigaro.fr/rss/figaro_actualites.xml",
    "https://www.lesechos.fr/": None,  # Anti-bot 403, no public RSS
    "https://www.lopinion.fr/": "https://www.lopinion.fr/index.rss",
    "https://www.lepoint.fr/": "https://www.lepoint.fr/rss.xml",
    "https://www.politico.eu/": "https://www.politico.eu/feed/",
    "https://www.commentaire.fr/": "https://shs.cairn.info/rss/revue/COMM",
    "https://www.lemonde.fr/": "https://www.lemonde.fr/rss/une.xml",
    "https://www.mediapart.fr/": "https://www.mediapart.fr/articles/feed",
    "https://www.liberation.fr/": "https://www.liberation.fr/rss/",
    "https://reporterre.net/": "https://reporterre.net/spip.php?page=backend-simple",
    "https://www.lecanardenchaine.fr/": "https://www.lecanardenchaine.fr/rss/index.xml",
    "https://www.sismique.world/": "https://rss.acast.com/sismique",
    "https://www.rtl.fr/": "https://www.rtl.fr/podcast/le-journal-rtl.xml",
    "https://www.ouest-france.fr/": "https://www.ouest-france.fr/rss/une",
    "https://www.francetvinfo.fr/": "https://www.francetvinfo.fr/titres.rss",
    "https://www.la-croix.com/": "https://www.la-croix.com/feeds/rss/site.xml",
    "https://www.tf1info.fr/": "https://www.tf1info.fr/flux-rss.xml",
    "https://www.midilibre.fr/": "https://www.midilibre.fr/rss",
    "https://www.cnews.fr/": "https://www.cnews.fr/rss", 
    "https://www.rts.ch/": "https://www.rts.ch/info/suisse?format=rss/news",
    "https://www.lecho.be/": "https://www.lecho.be/rss/actualite.xml",
    "https://rmc.bfmtv.com/": "https://rmc.bfmtv.com/rss/info/flux-rss/flux-toutes-les-actualites/",
}

# Standard Chrome User-Agent to avoid being blocked
DEFAULT_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
}

async def detect_youtube_feed(url: str, client: httpx.AsyncClient) -> Optional[str]:
    """Detect YouTube RSS feed URL from a channel URL."""
    if url in CURATED_FEED_FALLBACKS:
        return CURATED_FEED_FALLBACKS[url]

    channel_match = re.search(r"youtube\.com/channel/(UC[\w-]+)", url)
    if channel_match:
        channel_id = channel_match.group(1)
        return f"https://www.youtube.com/feeds/videos.xml?channel_id={channel_id}"
    
    try:
        response = await client.get(url, follow_redirects=True, headers=DEFAULT_HEADERS)
        if response.status_code == 200:
            id_match = re.search(r'"channelId":"(UC[\w-]+)"', response.text) or \
                       re.search(r'"externalId":"(UC[\w-]+)"', response.text)
            if id_match:
                return f"https://www.youtube.com/feeds/videos.xml?channel_id={id_match.group(1)}"
    except Exception as e:
        print(f"  ❌ YouTube detection error for {url}: {e}")
    return None

async def detect_site_feed(url: str, client: httpx.AsyncClient) -> Optional[str]:
    """Detect RSS feed for a website."""
    if url in CURATED_FEED_FALLBACKS:
        return CURATED_FEED_FALLBACKS[url]

    try:
        response = await client.get(url, follow_redirects=True, headers=DEFAULT_HEADERS)
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
    except Exception as e:
        print(f"  ❌ Site feed detection error for {url}: {e}")
    return None


def parse_granular_topics(topics_str: str, source_name: str) -> List[str]:
    """Parse granular_topics JSON from CSV. Returns empty list on failure."""
    if not topics_str or not topics_str.strip():
        return []
    
    try:
        topics = json.loads(topics_str)
        if isinstance(topics, list):
            return [str(t).strip() for t in topics if t]
        else:
            print(f"⚠️ Warning: granular_topics for {source_name} is not a list: {topics_str}")
            return []
    except json.JSONDecodeError as e:
        print(f"⚠️ Warning: Bad JSON for granular_topics in source {source_name}: {e}")
        return []


async def process_source(source_data: Dict[str, str], session: AsyncSession, client: httpx.AsyncClient):
    name = source_data.get("Name")
    url = source_data.get("URL")
    
    if not name or not url or name == "Name": # Skip empty rows or repeated headers
        return

    # --- STATUS LOGIC ---
    status = source_data.get("Status", "INDEXED").upper() # Default to INDEXED if missing
    
    if status == "ARCHIVED":
        print(f"📦 Source {name} is ARCHIVED. Skipping.")
        return

    is_curated = (status == "CURATED")
    
    csv_type = source_data.get("Type")
    csv_theme = source_data.get("Thème", "").lower().strip()
    rationale = source_data.get("Rationale")
    csv_bias = source_data.get("Bias", "unknown")
    csv_reliability = source_data.get("Reliability", "unknown")
    
    internal_type = TYPE_MAPPING.get(csv_type, "article")
    
    # Theme validation
    internal_theme = csv_theme
    if internal_theme not in VALID_THEMES:
        print(f"⚠️ Warning: Unknown theme '{internal_theme}' for {name}. Setting to 'other'.")
        internal_theme = "other"
    
    # Map bias string to enum value (handling hyphens etc)
    bias_val = csv_bias.lower()
    reliability_val = csv_reliability.lower()
    
    # Parse granular_topics (Story 4.1c Part 2/3)
    granular_topics = parse_granular_topics(source_data.get("granular_topics", ""), name)
    
    # Scores: Read from CSV, fallback to heuristics ONLY if missing
    def parse_score(val):
        try:
            return float(val) if val and val.strip() else None
        except ValueError:
            return None

    score_indep = parse_score(source_data.get("Score_Independence"))
    score_rigor = parse_score(source_data.get("Score_Rigor"))
    score_ux = parse_score(source_data.get("Score_UX"))
    
    # Fallback Heuristic if scores are missing (Legacy / Indexing phase)
    if score_indep is None:
        if reliability_val == "high":
            score_indep, score_rigor, score_ux = 0.9, 0.9, 0.8
        elif reliability_val in ["medium", "mixed"]:
            score_indep, score_rigor, score_ux = 0.6, 0.6, 0.6
        elif reliability_val == "low":
            score_indep, score_rigor, score_ux = 0.3, 0.3, 0.4

    feed_url = None
    if internal_type == "youtube":
        feed_url = await detect_youtube_feed(url, client)
    elif internal_type == "podcast" and "radiofrance.fr" in url:
        # Check curated fallbacks first; the old .rss suffix pattern no longer works
        feed_url = CURATED_FEED_FALLBACKS.get(url) or f"{url.rstrip('/')}.rss"
    else:
        feed_url = await detect_site_feed(url, client)
        
    if not feed_url:
        print(f"⚠️ Warning: No feed found for {name} ({url}). Skipping.")
        return

    # Generate logo URL
    from urllib.parse import urlparse
    domain = urlparse(url).netloc
    logo_url = f"https://www.google.com/s2/favicons?domain={domain}&sz=128"

    # Try to find by feed_url OR by original url to avoid easy dupes
    result = await session.execute(select(Source).where((Source.feed_url == feed_url) | (Source.url == url)))
    existing_source = result.scalars().first()
    
    if existing_source:
        print(f"🔄 Updating existing source: {name} [{status}]")
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
        existing_source.is_curated = is_curated
        existing_source.is_active = True # Revive if inactive
        # Story 4.1c Part 2/3: Update granular_topics
        existing_source.granular_topics = granular_topics if granular_topics else None
    else:
        print(f"✨ Creating new source: {name} ([{status}] Curated: {is_curated})")
        new_source = Source(
            name=name, url=url, feed_url=feed_url,
            type=SourceType(internal_type), theme=internal_theme,
            description=rationale, logo_url=logo_url,
            is_curated=is_curated, is_active=True,
            bias_stance=BiasStance(bias_val),
            reliability_score=ReliabilityScore(reliability_val),
            bias_origin=BiasOrigin.CURATED,
            score_independence=score_indep,
            score_rigor=score_rigor,
            score_ux=score_ux,
            # Story 4.1c Part 2/3: Set granular_topics
            granular_topics=granular_topics if granular_topics else None
        )
        session.add(new_source)

async def main():
    import argparse
    parser = argparse.ArgumentParser(description="Import sources from CSV")
    parser.add_argument("--file", type=str, default="sources/sources_master.csv", help="Path to CSV file relative to project root")
    parser.add_argument("--start-at", type=int, default=1, help="Row number to start at (1-indexed)")
    parser.add_argument("--limit", type=int, default=0, help="Maximum number of rows to process (0 for no limit)")
    args = parser.parse_args()

    # Resolve path relative to project root
    target_csv = os.path.join(PROJECT_ROOT, args.file)
    
    if not os.path.exists(target_csv):
        print(f"❌ CSV not found at {target_csv}")
        return

    from app.database import async_session_maker, init_db
    
    print("🛠️ Initializing database connection using app settings...")
    await init_db()

    print(f"📂 Reading from {target_csv}...")
    rows = []
    with open(target_csv, mode='r', encoding='utf-8') as csvfile:
        reader = csv.DictReader(csvfile)
        rows = list(reader)
    
    total_total_rows = len(rows)
    
    # Slice rows based on start_at and limit
    start_idx = max(0, args.start_at - 1)
    if args.limit > 0:
        rows = rows[start_idx : start_idx + args.limit]
    else:
        rows = rows[start_idx:]
        
    total_rows = len(rows)
    print(f"👉 Processing {total_rows} sources (Starting at row {args.start_at}, Total in file: {total_total_rows}).")

    async with httpx.AsyncClient(timeout=20.0) as client:
        for i, row in enumerate(rows, 1):
            current_row_num = start_idx + i
            name = row.get("Name")
            url = row.get("URL")
            
            if not name or not url or name == "Name": # Skip empty rows or repeated headers
                print(f"[{current_row_num}/{total_total_rows}] Skipping invalid/empty row...")
                continue
                
            print(f"[{current_row_num}/{total_total_rows}] Processing {name} ({url})...")
            try:
                async with async_session_maker() as session:
                    await process_source(row, session, client)
                    await session.commit()
                # Small sleep to be nice to CPUs and DB
                await asyncio.sleep(0.1) 
            except Exception as e:
                print(f"❌ Error processing {row.get('Name')} at row {current_row_num}: {e}")
                continue
            
    print("🎉 Import process finished!")

if __name__ == "__main__":
    asyncio.run(main())
