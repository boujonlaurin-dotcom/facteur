#!/usr/bin/env python3
"""Backfill historical articles from deep sources.

RSS feeds typically expose 10-200+ articles but the regular sync only
processes the 50 most recent. This script fetches ALL available entries
from each deep source feed and inserts the new ones.

Deep content is timeless — older articles are often MORE valuable for
the "pas de recul" feature than recent ones.

Usage:
    cd packages/api && source venv/bin/activate
    python scripts/backfill_deep_sources.py
"""

from __future__ import annotations

import asyncio
import datetime
import html
import sys
from pathlib import Path

import feedparser
import httpx

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.database import async_session_maker, engine
from app.models.content import Content
from app.models.enums import ContentType
from app.models.source import Source

USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)


async def fetch_feed(client: httpx.AsyncClient, url: str) -> feedparser.FeedParserDict | None:
    """Fetch and parse an RSS/Atom feed."""
    try:
        resp = await client.get(url, headers={"User-Agent": USER_AGENT}, timeout=30.0)
        if resp.status_code != 200:
            print(f"    HTTP {resp.status_code} for {url}")
            return None
        return feedparser.parse(resp.text)
    except Exception as e:
        print(f"    Fetch error: {e}")
        return None


def parse_entry(entry, source: Source) -> dict | None:
    """Parse a feed entry into content data (mirrors sync_service logic)."""
    title = entry.get("title", "")
    link = entry.get("link", "")
    guid = entry.get("id", link)

    if not link or not title:
        return None

    # Date handling
    published_at = None
    if hasattr(entry, "published_parsed") and entry.published_parsed:
        published_at = datetime.datetime(*entry.published_parsed[:6])
    elif hasattr(entry, "updated_parsed") and entry.updated_parsed:
        published_at = datetime.datetime(*entry.updated_parsed[:6])

    if not published_at:
        return None  # Skip entries without dates

    # Description
    description = None
    if "summary" in entry:
        desc = html.unescape(entry.summary)
        # Strip HTML tags (basic)
        import re
        desc = re.sub(r"<[^>]+>", " ", desc)
        desc = re.sub(r"\s+", " ", desc).strip()
        if desc:
            description = desc[:2000]

    return {
        "source_id": source.id,
        "title": title[:500],
        "url": link,
        "guid": guid[:500],
        "published_at": published_at,
        "content_type": ContentType.ARTICLE,
        "description": description,
        "is_paid": False,  # Deep sources are free by design
    }


async def backfill_source(session, client: httpx.AsyncClient, source: Source) -> int:
    """Backfill all available articles from a deep source feed."""
    print(f"\n  {source.name} ({source.feed_url})")

    feed = await fetch_feed(client, source.feed_url)
    if not feed or not feed.entries:
        print(f"    No entries found")
        return 0

    total_entries = len(feed.entries)
    new_count = 0

    for entry in feed.entries:  # ALL entries, no limit
        data = parse_entry(entry, source)
        if not data:
            continue

        # Dedup by GUID
        stmt = select(Content.id).where(Content.guid == data["guid"])
        result = await session.execute(stmt)
        if result.scalar():
            continue  # Already exists

        content = Content(**data)
        session.add(content)
        new_count += 1

    if new_count > 0:
        await session.commit()

    print(f"    Feed entries: {total_entries}, New inserted: {new_count}")
    return new_count


async def main():
    print("Backfill deep sources — fetching ALL available feed entries\n")

    # Load all deep sources
    async with async_session_maker() as session:
        stmt = (
            select(Source)
            .where(Source.source_tier == "deep", Source.is_active.is_(True))
            .order_by(Source.name)
        )
        result = await session.execute(stmt)
        sources = list(result.scalars().all())

    print(f"Deep sources: {len(sources)}")

    total_new = 0
    async with httpx.AsyncClient(follow_redirects=True) as client:
        for source in sources:
            async with async_session_maker() as session:
                try:
                    new = await backfill_source(session, client, source)
                    total_new += new
                except Exception as e:
                    print(f"    ERROR: {e}")
                    continue

    await engine.dispose()

    print(f"\n{'=' * 50}")
    print(f"  Total new articles inserted: {total_new}")
    print(f"{'=' * 50}")


if __name__ == "__main__":
    asyncio.run(main())
