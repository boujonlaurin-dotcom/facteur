"""
Mission 1 — Diagnostic YouTube & Reddit RSS
Tests the RSS parser directly (bypassing service-level blocks)
to identify where YouTube and Reddit URL handling fails.
"""

import asyncio
import sys
import time

import feedparser
import httpx
from bs4 import BeautifulSoup

# ─── Config ────────────────────────────────────────────────────
CLIENT_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
    "Accept-Language": "en-US,en;q=0.9",
}
CLIENT_COOKIES = {"CONSENT": "YES+cb.20210328-17-p0.en+FX+430"}
TIMEOUT = 10.0


# ─── YouTube Tests ─────────────────────────────────────────────

YOUTUBE_TESTS = [
    ("Handle URL", "https://www.youtube.com/@ScienceEtonnante"),
    ("Channel URL", "https://www.youtube.com/channel/UCaNlbnghtwlsGF-KzAFThqA"),
    ("Direct Atom Feed", "https://www.youtube.com/feeds/videos.xml?channel_id=UCaNlbnghtwlsGF-KzAFThqA"),
    ("Handle URL (Heu?reka)", "https://www.youtube.com/@Haboryme"),
    ("Short handle (no @)", "https://www.youtube.com/c/Fouloscopie"),
    ("Video URL", "https://www.youtube.com/watch?v=dQw4w9WgXcQ"),
]

REDDIT_TESTS = [
    ("Subreddit URL", "https://www.reddit.com/r/technology"),
    ("Subreddit RSS direct", "https://www.reddit.com/r/technology/.rss"),
    ("Subreddit top/week RSS", "https://www.reddit.com/r/technology/top/.rss?t=week"),
    ("Old Reddit RSS", "https://old.reddit.com/r/technology/.rss"),
    ("Subreddit (no www)", "https://reddit.com/r/worldnews"),
    ("Subreddit small", "https://www.reddit.com/r/selfhosted"),
    ("Subreddit RSS small", "https://www.reddit.com/r/selfhosted/.rss"),
]


async def test_fetch(client: httpx.AsyncClient, url: str) -> dict:
    """Fetch a URL and return status, content type, and content preview."""
    try:
        start = time.time()
        resp = await client.get(url)
        elapsed = time.time() - start
        content_type = resp.headers.get("content-type", "unknown")
        return {
            "status": resp.status_code,
            "content_type": content_type,
            "elapsed_ms": int(elapsed * 1000),
            "content_length": len(resp.text),
            "content_preview": resp.text[:500],
            "error": None,
        }
    except Exception as e:
        return {"status": None, "content_type": None, "elapsed_ms": 0, "content_length": 0, "content_preview": "", "error": str(e)}


async def test_feedparser(client: httpx.AsyncClient, url: str) -> dict:
    """Fetch URL and try to parse with feedparser."""
    try:
        resp = await client.get(url)
        resp.raise_for_status()
        content = resp.text

        loop = asyncio.get_event_loop()
        feed = await loop.run_in_executor(None, feedparser.parse, content)

        return {
            "bozo": feed.bozo,
            "bozo_exception": str(feed.bozo_exception) if feed.bozo else None,
            "version": feed.version,
            "feed_title": feed.feed.get("title", "N/A"),
            "entry_count": len(feed.entries),
            "first_entry_title": feed.entries[0].get("title", "N/A") if feed.entries else "N/A",
            "error": None,
        }
    except Exception as e:
        return {"bozo": None, "entry_count": 0, "error": str(e)}


async def test_html_autodiscovery(client: httpx.AsyncClient, url: str) -> dict:
    """Fetch URL, parse HTML, look for <link rel='alternate'> RSS tags."""
    try:
        resp = await client.get(url)
        resp.raise_for_status()
        soup = BeautifulSoup(resp.text, "html.parser")

        rss_links = []
        for link in soup.find_all("link", rel="alternate"):
            type_attr = link.get("type", "").lower()
            href = link.get("href")
            if any(x in type_attr for x in ["rss", "atom", "xml"]):
                rss_links.append({"type": type_attr, "href": href})

        # YouTube: check for channelId meta
        channel_id = None
        meta_cid = soup.find("meta", itemprop="channelId")
        if meta_cid:
            channel_id = meta_cid.get("content")
        if not channel_id:
            import re
            match = re.search(r'"channelId":"(UC[\w-]+)"', resp.text)
            if match:
                channel_id = match.group(1)

        return {
            "rss_links_found": rss_links,
            "youtube_channel_id": channel_id,
            "page_title": soup.title.string if soup.title else "N/A",
            "error": None,
        }
    except Exception as e:
        return {"rss_links_found": [], "youtube_channel_id": None, "error": str(e)}


async def run_youtube_tests(client: httpx.AsyncClient) -> list[dict]:
    """Run all YouTube test cases."""
    results = []
    for label, url in YOUTUBE_TESTS:
        print(f"\n{'='*60}")
        print(f"  YOUTUBE TEST: {label}")
        print(f"  URL: {url}")
        print(f"{'='*60}")

        # Step 1: Raw fetch
        fetch = await test_fetch(client, url)
        print(f"\n  [FETCH] Status: {fetch['status']} | Content-Type: {fetch['content_type']} | {fetch['elapsed_ms']}ms | {fetch['content_length']} bytes")
        if fetch["error"]:
            print(f"  [FETCH] ERROR: {fetch['error']}")

        # Step 2: Feedparser attempt
        fp = await test_feedparser(client, url)
        print(f"  [FEEDPARSER] Bozo: {fp['bozo']} | Version: {fp.get('version', 'N/A')} | Entries: {fp['entry_count']} | Title: {fp.get('feed_title', 'N/A')}")
        if fp["error"]:
            print(f"  [FEEDPARSER] ERROR: {fp['error']}")
        if fp["entry_count"] > 0:
            print(f"  [FEEDPARSER] First entry: {fp['first_entry_title']}")

        # Step 3: HTML auto-discovery
        disco = await test_html_autodiscovery(client, url)
        print(f"  [AUTODISCOVERY] RSS links: {disco['rss_links_found']}")
        print(f"  [AUTODISCOVERY] YouTube channel_id: {disco['youtube_channel_id']}")
        if disco["error"]:
            print(f"  [AUTODISCOVERY] ERROR: {disco['error']}")

        # Step 4: If channel_id found, test the Atom feed
        if disco.get("youtube_channel_id"):
            atom_url = f"https://www.youtube.com/feeds/videos.xml?channel_id={disco['youtube_channel_id']}"
            print(f"\n  [ATOM FEED] Resolved URL: {atom_url}")
            atom_fp = await test_feedparser(client, atom_url)
            print(f"  [ATOM FEED] Entries: {atom_fp['entry_count']} | Title: {atom_fp.get('feed_title', 'N/A')}")
            if atom_fp["entry_count"] > 0:
                print(f"  [ATOM FEED] Latest: {atom_fp['first_entry_title']}")
            if atom_fp["error"]:
                print(f"  [ATOM FEED] ERROR: {atom_fp['error']}")

        results.append({
            "label": label,
            "url": url,
            "fetch": fetch,
            "feedparser": fp,
            "autodiscovery": disco,
        })

    return results


async def run_reddit_tests(client: httpx.AsyncClient) -> list[dict]:
    """Run all Reddit test cases."""
    results = []
    for label, url in REDDIT_TESTS:
        print(f"\n{'='*60}")
        print(f"  REDDIT TEST: {label}")
        print(f"  URL: {url}")
        print(f"{'='*60}")

        # Step 1: Raw fetch
        fetch = await test_fetch(client, url)
        print(f"\n  [FETCH] Status: {fetch['status']} | Content-Type: {fetch['content_type']} | {fetch['elapsed_ms']}ms | {fetch['content_length']} bytes")
        if fetch["error"]:
            print(f"  [FETCH] ERROR: {fetch['error']}")

        # Step 2: Feedparser
        fp = await test_feedparser(client, url)
        print(f"  [FEEDPARSER] Bozo: {fp['bozo']} | Version: {fp.get('version', 'N/A')} | Entries: {fp['entry_count']} | Title: {fp.get('feed_title', 'N/A')}")
        if fp["error"]:
            print(f"  [FEEDPARSER] ERROR: {fp['error']}")
        if fp["entry_count"] > 0:
            print(f"  [FEEDPARSER] First entry: {fp['first_entry_title']}")

        # Step 3: HTML auto-discovery
        disco = await test_html_autodiscovery(client, url)
        print(f"  [AUTODISCOVERY] RSS links: {disco['rss_links_found']}")
        if disco["error"]:
            print(f"  [AUTODISCOVERY] ERROR: {disco['error']}")

        results.append({
            "label": label,
            "url": url,
            "fetch": fetch,
            "feedparser": fp,
            "autodiscovery": disco,
        })

    return results


async def main():
    print("=" * 70)
    print("  MISSION 1 — YouTube & Reddit RSS Diagnostic")
    print("  Testing RSS parser detection pipeline")
    print("=" * 70)

    async with httpx.AsyncClient(
        timeout=TIMEOUT,
        follow_redirects=True,
        headers=CLIENT_HEADERS,
        cookies=CLIENT_COOKIES,
    ) as client:
        print("\n\n" + "#" * 70)
        print("#  PART 1: YOUTUBE TESTS")
        print("#" * 70)
        yt_results = await run_youtube_tests(client)

        print("\n\n" + "#" * 70)
        print("#  PART 2: REDDIT TESTS")
        print("#" * 70)
        reddit_results = await run_reddit_tests(client)

    # Summary
    print("\n\n" + "=" * 70)
    print("  SUMMARY")
    print("=" * 70)

    print("\n  YOUTUBE:")
    for r in yt_results:
        status = "PASS" if r["feedparser"]["entry_count"] > 0 or (r["autodiscovery"].get("youtube_channel_id")) else "FAIL"
        print(f"    [{status}] {r['label']}: entries={r['feedparser']['entry_count']}, channel_id={r['autodiscovery'].get('youtube_channel_id', 'N/A')}")

    print("\n  REDDIT:")
    for r in reddit_results:
        status = "PASS" if r["feedparser"]["entry_count"] > 0 else "FAIL"
        print(f"    [{status}] {r['label']}: entries={r['feedparser']['entry_count']}, rss_links={len(r['autodiscovery']['rss_links_found'])}")


if __name__ == "__main__":
    asyncio.run(main())
