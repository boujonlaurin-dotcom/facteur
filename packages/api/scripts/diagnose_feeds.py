#!/usr/bin/env python3
"""
Script de diagnostic pour tester les sources RSS.
Usage: cd packages/api && python3 scripts/diagnose_feeds.py
"""

import asyncio
import httpx
import feedparser
import certifi
from datetime import datetime

# Liste des sources à tester (copier depuis la base ou sources.csv)
# Pour l'instant, on teste quelques sources connues
TEST_SOURCES = []

async def test_feed(client: httpx.AsyncClient, name: str, url: str) -> dict:
    """Teste une source RSS et retourne le résultat."""
    result = {
        "name": name,
        "url": url,
        "status": "unknown",
        "http_status": None,
        "entries_count": 0,
        "error": None,
        "latest_entry": None,
    }
    
    try:
        response = await client.get(url)
        result["http_status"] = response.status_code
        
        if response.status_code != 200:
            result["status"] = "http_error"
            result["error"] = f"HTTP {response.status_code}"
            return result
        
        feed = feedparser.parse(response.text)
        
        if feed.bozo:
            result["status"] = "parse_warning"
            result["error"] = str(feed.bozo_exception)
        
        result["entries_count"] = len(feed.entries)
        
        if feed.entries:
            result["status"] = "ok"
            latest = feed.entries[0]
            result["latest_entry"] = {
                "title": latest.get("title", "No title")[:50],
                "date": str(latest.get("published", latest.get("updated", "Unknown"))),
            }
        else:
            result["status"] = "no_entries"
            result["error"] = "Feed has no entries"
            
    except httpx.TimeoutException:
        result["status"] = "timeout"
        result["error"] = "Request timed out (30s)"
    except httpx.ConnectError as e:
        result["status"] = "connect_error"
        result["error"] = str(e)
    except Exception as e:
        result["status"] = "error"
        result["error"] = str(e)
    
    return result

async def main():
    """Teste toutes les sources et affiche un rapport."""
    print("=" * 80)
    print("📡 RSS Feed Diagnostic Tool")
    print("=" * 80)
    print()
    
    # If no test sources defined, fetch from database
    if not TEST_SOURCES:
        print("📚 Fetching sources from database...")
        try:
            import sys
            sys.path.insert(0, '.')
            from app.database import async_session_maker
            from app.models.source import Source
            from sqlalchemy import select
            
            async with async_session_maker() as session:
                result = await session.execute(
                    select(Source).where(Source.is_active == True)
                )
                sources = result.scalars().all()
                for s in sources:
                    TEST_SOURCES.append((s.name, s.feed_url))
                print(f"   Found {len(TEST_SOURCES)} active sources")
        except Exception as e:
            print(f"❌ Could not fetch from DB: {e}")
            print("   Using hardcoded test sources instead")
            TEST_SOURCES.extend([
                ("Le Monde", "https://www.lemonde.fr/rss/une.xml"),
                ("Libération", "https://www.liberation.fr/arc/outboundfeeds/rss/?outputType=xml"),
                ("20 Minutes", "https://www.20minutes.fr/feeds/rss-une.xml"),
            ])
    
    print()
    
    async with httpx.AsyncClient(
        timeout=30.0,
        follow_redirects=True,
        verify=certifi.where(),
        headers={"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"}
    ) as client:
        
        results = []
        for name, url in TEST_SOURCES:
            print(f"🔍 Testing: {name}...", end=" ", flush=True)
            result = await test_feed(client, name, url)
            results.append(result)
            
            if result["status"] == "ok":
                print(f"✅ OK ({result['entries_count']} entries)")
            elif result["status"] == "parse_warning":
                print(f"⚠️  Warning: {result['error'][:50]} ({result['entries_count']} entries)")
            else:
                print(f"❌ FAILED: {result['error']}")
    
    # Summary
    print()
    print("=" * 80)
    print("📊 SUMMARY")
    print("=" * 80)
    
    ok = [r for r in results if r["status"] == "ok"]
    warnings = [r for r in results if r["status"] == "parse_warning"]
    failed = [r for r in results if r["status"] not in ("ok", "parse_warning")]
    
    print(f"✅ OK: {len(ok)}")
    print(f"⚠️  Warnings: {len(warnings)}")
    print(f"❌ Failed: {len(failed)}")
    
    if failed:
        print()
        print("❌ FAILED SOURCES:")
        for r in failed:
            print(f"   - {r['name']}: {r['error']}")
            print(f"     URL: {r['url']}")

if __name__ == "__main__":
    asyncio.run(main())
