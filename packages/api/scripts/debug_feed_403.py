import asyncio
import sys
import os

# Ensure we can import app
sys.path.append(os.path.join(os.path.dirname(__file__), '../'))

from app.utils.rss_parser import RSSParser
import structlog

# Configure structlog to see logs
structlog.configure(
    processors=[structlog.processors.JSONRenderer()],
    logger_factory=structlog.PrintLoggerFactory(),
)

async def test_fallback():
    parser = RSSParser(timeout=10)
    
    # URL known to block python-httpx (Libération or AP News)
    # If Libération works, try another WAF protected site.
    url = "https://www.liberation.fr/arc/outboundfeeds/rss/?outputType=xml" 
    
    print(f"📡 Testing Fetch for {url}...")
    try:
        result = await parser.parse(url)
        print("✅ Success!")
        print(f"Title: {result.get('title')}")
        print(f"Entries: {len(result.get('entries', []))}")
    except Exception as e:
        print(f"❌ Failed with {type(e).__name__}: {e}")

if __name__ == "__main__":
    asyncio.run(test_fallback())
