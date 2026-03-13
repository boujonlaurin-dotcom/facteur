#!/usr/bin/env python3
"""Backfill deep YouTube channels — fetch ALL videos via YouTube Data API v3.

Adds educational/analytical YouTube channels as deep sources and imports
their full video history. These videos are timeless "pas de recul" content.

Usage:
    cd packages/api && source venv/bin/activate
    python scripts/backfill_youtube_deep.py
"""

from __future__ import annotations

import asyncio
import datetime
import sys
from pathlib import Path
from uuid import uuid4

import httpx

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import select

from app.config import get_settings
from app.database import async_session_maker, engine
from app.models.content import Content
from app.models.enums import (
    BiasOrigin,
    BiasStance,
    ContentType,
    ReliabilityScore,
    SourceType,
)
from app.models.source import Source

settings = get_settings()
API_KEY = settings.youtube_api_key

if not API_KEY:
    print("ERROR: YOUTUBE_API_KEY not set in .env")
    sys.exit(1)

# ── Deep YouTube channels ───────────────────────────────────────────────────
# Format: (name, channel_handle_or_id, theme, granular_topics, description)
# channel_handle will be resolved to channel_id via API

DEEP_YOUTUBE_CHANNELS = [
    {
        "name": "Le Réveilleur",
        "handle": "@LeReworkeilleur",
        "channel_id": "UCNovJemYKcdKt7PDdptJZfQ",
        "theme": "environment",
        "granular_topics": ["climate", "energy-transition", "applied-science"],
        "description": "Analyses approfondies sur l'énergie et le climat. Vulgarisation scientifique rigoureuse et sourcée.",
    },
    {
        "name": "Heu?reka",
        "handle": "@Heureka",
        "channel_id": "UC7sXGI8p8PvKosLWagkK9wQ",
        "theme": "economy",
        "granular_topics": ["finance", "economy", "applied-science"],
        "description": "Vulgarisation économique et financière. Décryptage des mécanismes économiques avec rigueur analytique.",
    },
    {
        "name": "Science4All",
        "handle": "@Science4All",
        "channel_id": "UC0NCbj8CxzeCGIF6sODJ-7A",
        "theme": "science",
        "granular_topics": ["fundamental-research", "applied-science", "data-privacy"],
        "description": "Mathématiques, IA et science. Analyses de fond sur les implications sociétales de la technologie.",
    },
    {
        "name": "Monsieur Bidouille",
        "handle": "@MrBidouille",
        "channel_id": "UCSULDz1yaHLVQWHpm4g_GHA",
        "theme": "tech",
        "granular_topics": ["energy-transition", "applied-science", "cleantech"],
        "description": "Vulgarisation technique et industrielle. Énergie, infrastructures et innovations technologiques.",
    },
    {
        "name": "Philoxime",
        "handle": "@Philoxime",
        "channel_id": "UCdKTlsmvczkdvGjiLinQwmw",
        "theme": "culture",
        "granular_topics": ["philosophy", "democracy", "social-justice"],
        "description": "Philosophie politique et éthique appliquée. Analyses de fond sur la démocratie et la justice sociale.",
    },
    {
        "name": "ScienceÉtonnante",
        "handle": "@ScienceEtonnante",
        "channel_id": "UCaNlbnghtwlsGF-KzAFThqA",
        "theme": "science",
        "granular_topics": ["fundamental-research", "applied-science"],
        "description": "Vulgarisation scientifique de haut niveau. Physique, mathématiques et sciences cognitives.",
    },
    {
        "name": "Éthique et tac",
        "handle": "@ethiqueettac",
        "channel_id": None,  # Will resolve via API
        "theme": "culture",
        "granular_topics": ["philosophy", "social-justice"],
        "description": "Éthique appliquée et questions de société. Réflexions philosophiques accessibles sur les enjeux contemporains.",
    },
]


async def resolve_channel_id(client: httpx.AsyncClient, handle: str) -> str | None:
    """Resolve a YouTube handle to a channel ID via API."""
    # Try search
    resp = await client.get(
        "https://www.googleapis.com/youtube/v3/search",
        params={"part": "snippet", "q": handle, "type": "channel", "maxResults": 1, "key": API_KEY},
    )
    if resp.status_code == 200:
        items = resp.json().get("items", [])
        if items:
            return items[0]["snippet"]["channelId"]
    return None


async def get_uploads_playlist_id(client: httpx.AsyncClient, channel_id: str) -> str | None:
    """Get the 'uploads' playlist ID for a channel."""
    resp = await client.get(
        "https://www.googleapis.com/youtube/v3/channels",
        params={"part": "contentDetails", "id": channel_id, "key": API_KEY},
    )
    if resp.status_code == 200:
        items = resp.json().get("items", [])
        if items:
            return items[0]["contentDetails"]["relatedPlaylists"]["uploads"]
    return None


async def fetch_all_videos(client: httpx.AsyncClient, playlist_id: str) -> list[dict]:
    """Fetch ALL videos from a playlist using pagination."""
    videos = []
    page_token = None

    while True:
        params = {
            "part": "snippet",
            "playlistId": playlist_id,
            "maxResults": 50,
            "key": API_KEY,
        }
        if page_token:
            params["pageToken"] = page_token

        resp = await client.get(
            "https://www.googleapis.com/youtube/v3/playlistItems",
            params=params,
        )

        if resp.status_code != 200:
            print(f"    API error {resp.status_code}: {resp.text[:200]}")
            break

        data = resp.json()
        for item in data.get("items", []):
            snippet = item["snippet"]
            video_id = snippet.get("resourceId", {}).get("videoId")
            if not video_id:
                continue

            published = snippet.get("publishedAt", "")
            try:
                pub_dt = datetime.datetime.fromisoformat(published.replace("Z", "+00:00"))
            except (ValueError, AttributeError):
                pub_dt = datetime.datetime.utcnow()

            videos.append({
                "video_id": video_id,
                "title": snippet.get("title", "")[:500],
                "description": (snippet.get("description", "") or "")[:2000],
                "published_at": pub_dt,
                "thumbnail_url": (snippet.get("thumbnails", {}).get("high", {}) or {}).get("url"),
            })

        page_token = data.get("nextPageToken")
        if not page_token:
            break

    return videos


async def ensure_source(session, channel_info: dict, channel_id: str) -> Source:
    """Create or update a YouTube deep source."""
    feed_url = f"https://www.youtube.com/feeds/videos.xml?channel_id={channel_id}"
    url = f"https://www.youtube.com/channel/{channel_id}"
    logo_url = f"https://www.google.com/s2/favicons?domain=youtube.com&sz=128"

    stmt = select(Source).where(Source.feed_url == feed_url)
    result = await session.execute(stmt)
    source = result.scalars().first()

    if source:
        source.source_tier = "deep"
        source.is_active = True
        print(f"    Source exists, updated to deep tier")
    else:
        source = Source(
            id=uuid4(),
            name=channel_info["name"],
            url=url,
            feed_url=feed_url,
            type=SourceType.YOUTUBE,
            theme=channel_info["theme"],
            description=channel_info["description"],
            logo_url=logo_url,
            is_curated=True,
            is_active=True,
            source_tier="deep",
            bias_stance=BiasStance.SPECIALIZED,
            reliability_score=ReliabilityScore.HIGH,
            bias_origin=BiasOrigin.CURATED,
            score_independence=0.9,
            score_rigor=0.9,
            score_ux=0.8,
            granular_topics=channel_info["granular_topics"],
            created_at=datetime.datetime.utcnow(),
        )
        session.add(source)
        print(f"    Created new source")

    await session.flush()
    return source


async def backfill_channel(session, client: httpx.AsyncClient, channel_info: dict) -> int:
    """Backfill all videos from a YouTube channel."""
    name = channel_info["name"]
    print(f"\n  {name}")

    # Resolve channel ID
    channel_id = channel_info.get("channel_id")
    if not channel_id:
        channel_id = await resolve_channel_id(client, channel_info["handle"])
        if not channel_id:
            print(f"    Could not resolve channel ID for {channel_info['handle']}")
            return 0
        print(f"    Resolved channel_id: {channel_id}")

    # Ensure source exists
    source = await ensure_source(session, channel_info, channel_id)

    # Get uploads playlist
    playlist_id = await get_uploads_playlist_id(client, channel_id)
    if not playlist_id:
        print(f"    Could not get uploads playlist")
        return 0

    # Fetch all videos
    videos = await fetch_all_videos(client, playlist_id)
    print(f"    Videos found: {len(videos)}")

    # Insert new ones
    new_count = 0
    for video in videos:
        guid = f"yt:video:{video['video_id']}"
        url = f"https://www.youtube.com/watch?v={video['video_id']}"

        stmt = select(Content.id).where(Content.guid == guid)
        result = await session.execute(stmt)
        if result.scalar():
            continue

        content = Content(
            source_id=source.id,
            title=video["title"],
            url=url,
            guid=guid,
            published_at=video["published_at"],
            content_type=ContentType.YOUTUBE,
            description=video["description"],
            thumbnail_url=video["thumbnail_url"],
            is_paid=False,
        )
        session.add(content)
        new_count += 1

    if new_count > 0:
        await session.commit()
    else:
        await session.commit()  # Commit source changes

    print(f"    New videos inserted: {new_count}")
    return new_count


async def main():
    print("Backfill deep YouTube channels — full video history\n")
    print(f"API key: ...{API_KEY[-4:]}")
    print(f"Channels: {len(DEEP_YOUTUBE_CHANNELS)}")

    total_new = 0
    async with httpx.AsyncClient(timeout=30.0) as client:
        for channel_info in DEEP_YOUTUBE_CHANNELS:
            async with async_session_maker() as session:
                try:
                    new = await backfill_channel(session, client, channel_info)
                    total_new += new
                except Exception as e:
                    print(f"    ERROR: {e}")
                    import traceback
                    traceback.print_exc()
                    continue

    await engine.dispose()

    print(f"\n{'=' * 50}")
    print(f"  Total new videos inserted: {total_new}")
    print(f"{'=' * 50}")


if __name__ == "__main__":
    asyncio.run(main())
