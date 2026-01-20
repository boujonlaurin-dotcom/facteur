
import asyncio
import httpx
import feedparser
from app.utils.rss_parser import RSSParser

URLS = [
    "https://apnews.com/index.rss",
    "https://www.liberation.fr/arc/outboundfeeds/rss-all/",
    # "https://www.commentaire.fr/feed/", # Disabled by server
]

async def test_feeds():
    parser = RSSParser()
    
    print("------- TESTING RSS FETCHING -------")
    print(f"User-Agent Strategy: {parser.user_agent if hasattr(parser, 'user_agent') else 'Default httpx'}")
    
    for url in URLS:
        print(f"\nTarget: {url}")
        try:
            data = await parser.parse(url)
            print(f"✅ Success! Title: {data.get('title')} ({len(data.get('entries', []))} entries)")
        except Exception as e:
            print(f"❌ Failed: {e}")

if __name__ == "__main__":
    asyncio.run(test_feeds())
