#!/usr/bin/env python3
"""Fix Le Réveilleur: delete Jancovici fan channel, backfill real one."""

from __future__ import annotations

import asyncio
import datetime
import sys
from pathlib import Path
from uuid import UUID

import httpx

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import select, delete
from app.database import async_session_maker, engine
from app.models.source import Source
from app.models.content import Content
from app.models.enums import ContentType
from app.config import get_settings

API_KEY = get_settings().youtube_api_key
WRONG_SOURCE_ID = UUID("62856ee2-4434-47c1-b2a7-f38eccbe8f18")  # Jancovici fan channel
REAL_SOURCE_ID = UUID("583ac86a-3e28-4a89-a3d3-9b9375b9b8f9")   # Real Le Réveilleur
REAL_CID = "UC1EacOJoqsKaYxaDomTCTEQ"


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
                pub_dt = datetime.datetime.now(datetime.UTC)
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
    async with async_session_maker() as session:
        # Step 1: Delete contents + source for the wrong Jancovici channel
        del_contents = await session.execute(
            delete(Content).where(Content.source_id == WRONG_SOURCE_ID)
        )
        print(f"Deleted {del_contents.rowcount} Jancovici clips")

        del_source = await session.execute(
            delete(Source).where(Source.id == WRONG_SOURCE_ID)
        )
        print(f"Deleted {del_source.rowcount} wrong source")
        await session.commit()

    # Step 2: Backfill real Le Réveilleur via YouTube API
    async with httpx.AsyncClient(timeout=30) as client:
        async with async_session_maker() as session:
            playlist_id = await get_uploads_playlist(client, REAL_CID)
            videos = await fetch_all_videos(client, playlist_id)
            print(f"Real Le Réveilleur videos from API: {len(videos)}")

            new_count = 0
            for v in videos:
                guid = f"yt:video:{v['video_id']}"
                exists = await session.execute(select(Content.id).where(Content.guid == guid))
                if exists.scalar():
                    continue
                session.add(Content(
                    source_id=REAL_SOURCE_ID, title=v["title"],
                    url=f"https://www.youtube.com/watch?v={v['video_id']}",
                    guid=guid, published_at=v["published_at"],
                    content_type=ContentType.YOUTUBE,
                    description=v["description"],
                    thumbnail_url=v["thumbnail_url"], is_paid=False,
                ))
                new_count += 1

            await session.commit()
            print(f"New videos inserted: {new_count}")

    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
