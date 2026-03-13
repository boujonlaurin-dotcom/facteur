#!/usr/bin/env python3
"""Backfill 8 new YouTube deep channels + remove Éthique et tac from deep pool."""

from __future__ import annotations

import asyncio
import datetime
import sys
from pathlib import Path
from uuid import uuid4

import httpx

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import select
from app.database import async_session_maker, engine
from app.models.source import Source
from app.models.content import Content
from app.models.enums import SourceType, ContentType, BiasStance, ReliabilityScore, BiasOrigin
from app.config import get_settings

API_KEY = get_settings().youtube_api_key

NEW_CHANNELS = [
    {
        "name": "Osons Causer", "channel_id": "UCVeMw72tepFl1Zt5fvf9QKQ",
        "theme": "politics", "granular_topics": ["democracy", "social-justice", "institutions"],
        "description": "Décryptage politique et citoyen. Analyses des institutions, mouvements sociaux et enjeux démocratiques.",
    },
    {
        "name": "Chez Anatole", "channel_id": "UCNn9eZpA6X2VCRzkUHwxgyg",
        "theme": "culture", "granular_topics": ["philosophy", "social-justice", "democracy"],
        "description": "Philosophie et sciences sociales. Réflexions de fond sur les inégalités, la justice et la société.",
    },
    {
        "name": "Monsieur Phi", "channel_id": "UCqA8H22FwgBVcF3GJpp0MQw",
        "theme": "culture", "granular_topics": ["philosophy", "applied-science", "democracy"],
        "description": "Philosophie analytique et logique. Analyses rigoureuses des arguments, biais cognitifs et éthique.",
    },
    {
        "name": "Stupid Economics", "channel_id": "UCyJDHgrsUKuWLe05GvC2lng",
        "theme": "economy", "granular_topics": ["economy", "finance", "applied-science"],
        "description": "Vulgarisation économique. Décryptage des mécanismes économiques, politiques monétaires et inégalités.",
    },
    {
        "name": "AprèsLaBière", "channel_id": "UCX8dmzDECYUAlEanzSqQXBA",
        "theme": "culture", "granular_topics": ["philosophy", "social-justice"],
        "description": "Philosophie politique accessible. Réflexions sur la société, les médias et les rapports de pouvoir.",
    },
    {
        "name": "La Fabrique Sociale", "channel_id": "UCJfgnn1fhvp0GH-e-FVepcg",
        "theme": "culture", "granular_topics": ["social-justice", "democracy", "philosophy"],
        "description": "Sciences sociales et sociologie. Analyses des structures sociales, discriminations et mobilisations.",
    },
    {
        "name": "Hygiène Mentale", "channel_id": "UCMFcMhePnH4onVHt2-ItPZw",
        "theme": "science", "granular_topics": ["applied-science", "fundamental-research", "data-privacy"],
        "description": "Esprit critique et zététique. Analyse des biais cognitifs, méthode scientifique et désinformation.",
    },
    {
        "name": "Fouloscopie", "channel_id": "UCLXDNUOO3EQ80VmD9nQBHPg",
        "theme": "science", "granular_topics": ["applied-science", "fundamental-research"],
        "description": "Science des foules et comportements collectifs. Physique sociale, simulations et dynamiques de groupe.",
    },
]


async def get_uploads_playlist(client, channel_id):
    resp = await client.get(
        "https://www.googleapis.com/youtube/v3/channels",
        params={"part": "contentDetails", "id": channel_id, "key": API_KEY},
    )
    items = resp.json().get("items", [])
    if items:
        return items[0]["contentDetails"]["relatedPlaylists"]["uploads"]
    return None


async def fetch_all_videos(client, playlist_id):
    videos = []
    page_token = None
    while True:
        params = {"part": "snippet", "playlistId": playlist_id, "maxResults": 50, "key": API_KEY}
        if page_token:
            params["pageToken"] = page_token
        resp = await client.get("https://www.googleapis.com/youtube/v3/playlistItems", params=params)
        if resp.status_code != 200:
            print(f"    API error {resp.status_code}")
            break
        data = resp.json()
        for item in data.get("items", []):
            sn = item["snippet"]
            vid = sn.get("resourceId", {}).get("videoId")
            if not vid:
                continue
            pub = sn.get("publishedAt", "")
            try:
                pub_dt = datetime.datetime.fromisoformat(pub.replace("Z", "+00:00"))
            except (ValueError, AttributeError):
                pub_dt = datetime.datetime.utcnow()
            videos.append({
                "video_id": vid,
                "title": sn.get("title", "")[:500],
                "description": (sn.get("description", "") or "")[:2000],
                "published_at": pub_dt,
                "thumbnail_url": (sn.get("thumbnails", {}).get("high", {}) or {}).get("url"),
            })
        page_token = data.get("nextPageToken")
        if not page_token:
            break
    return videos


async def main():
    print("Backfill 8 new YouTube deep channels\n")
    total_new = 0

    async with httpx.AsyncClient(timeout=30) as client:
        for ch in NEW_CHANNELS:
            print(f"\n  {ch['name']}")

            async with async_session_maker() as session:
                feed_url = f"https://www.youtube.com/feeds/videos.xml?channel_id={ch['channel_id']}"
                url = f"https://www.youtube.com/channel/{ch['channel_id']}"

                stmt = select(Source).where(Source.feed_url == feed_url)
                result = await session.execute(stmt)
                source = result.scalars().first()

                if not source:
                    source = Source(
                        id=uuid4(), name=ch["name"], url=url, feed_url=feed_url,
                        type=SourceType.YOUTUBE, theme=ch["theme"],
                        description=ch["description"],
                        logo_url="https://www.google.com/s2/favicons?domain=youtube.com&sz=128",
                        is_curated=True, is_active=True, source_tier="deep",
                        bias_stance=BiasStance.SPECIALIZED,
                        reliability_score=ReliabilityScore.HIGH,
                        bias_origin=BiasOrigin.CURATED,
                        score_independence=0.9, score_rigor=0.9, score_ux=0.8,
                        granular_topics=ch["granular_topics"],
                        created_at=datetime.datetime.utcnow(),
                    )
                    session.add(source)
                    await session.flush()
                    print("    Source created")
                else:
                    print("    Source exists")

                source_id = source.id

                playlist_id = await get_uploads_playlist(client, ch["channel_id"])
                if not playlist_id:
                    print("    No uploads playlist")
                    await session.commit()
                    continue

                videos = await fetch_all_videos(client, playlist_id)
                print(f"    Videos found: {len(videos)}")

                new_count = 0
                for v in videos:
                    guid = f"yt:video:{v['video_id']}"
                    exists = await session.execute(select(Content.id).where(Content.guid == guid))
                    if exists.scalar():
                        continue
                    session.add(Content(
                        source_id=source_id, title=v["title"],
                        url=f"https://www.youtube.com/watch?v={v['video_id']}",
                        guid=guid, published_at=v["published_at"],
                        content_type=ContentType.YOUTUBE,
                        description=v["description"],
                        thumbnail_url=v["thumbnail_url"], is_paid=False,
                    ))
                    new_count += 1

                await session.commit()
                print(f"    New inserted: {new_count}")
                total_new += new_count

    # Remove Éthique et tac from deep pool
    async with async_session_maker() as session:
        stmt = select(Source).where(Source.name == "Éthique et tac")
        result = await session.execute(stmt)
        ethique = result.scalars().first()
        if ethique:
            ethique.source_tier = "mainstream"
            ethique.is_active = False
            await session.commit()
            print("\n  Éthique et tac → tier='mainstream', is_active=False")

    await engine.dispose()
    print(f"\n{'=' * 50}")
    print(f"  Total new videos: {total_new}")
    print(f"{'=' * 50}")


if __name__ == "__main__":
    asyncio.run(main())
