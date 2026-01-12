"""Test Google News RSS quality for perspective discovery."""

import asyncio
import httpx
import xml.etree.ElementTree as ET
from urllib.parse import quote

async def test_google_news(keywords: str):
    """Test Google News RSS with given keywords."""
    query = quote(keywords)
    url = f"https://news.google.com/rss/search?q={query}&hl=fr&gl=FR&ceid=FR:fr"
    
    print(f"🔍 Query: {keywords}")
    print(f"📡 URL: {url[:80]}...")
    print("-" * 60)
    
    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.get(url)
        
        if response.status_code != 200:
            print(f"❌ Error: {response.status_code}")
            return
        
        root = ET.fromstring(response.content)
        items = root.findall(".//item")
        
        print(f"📰 Found {len(items)} results:\n")
        
        for item in items[:8]:
            title = item.find("title").text if item.find("title") is not None else "?"
            source = item.find("source").text if item.find("source") is not None else "?"
            pub_date = item.find("pubDate").text if item.find("pubDate") is not None else "?"
            
            print(f"  [{source:20}] {title[:60]}...")
            print(f"                        📅 {pub_date[:25]}")
            print()


async def main():
    # Test with different article topics
    test_cases = [
        "Trump Venezuela",
        "Groenland Danemark",
        "IA intelligence artificielle régulation",
    ]
    
    for keywords in test_cases:
        await test_google_news(keywords)
        print("\n" + "=" * 60 + "\n")


if __name__ == "__main__":
    asyncio.run(main())
