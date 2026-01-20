import asyncio
import sys
import os

# Ensure we can import app
sys.path.append(os.path.join(os.path.dirname(__file__), '../'))

from app.utils.rss_parser import RSSParser

async def test_rss_fetch():
    print("🚀 Starting RSS Fetch Test with curl_cffi...")
    parser = RSSParser(timeout=10)
    
    # URL known to be tricky but standard
    url = "https://www.lemonde.fr/rss/une.xml" 
    
    print(f"📡 Fetching {url}...")
    try:
        result = await parser.parse(url)
        print(f"✅ Success! Title: {result.get('title')}")
    except Exception as e:
        print(f"❌ Error: {e}")

async def main():
    # Simulate uvicorn-like loop behavior if possible, but asyncio.run is usually standard
    print(f"🐍 Python {sys.version}")
    await test_rss_fetch()
    print("🏁 Done.")

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n⛔️ Interrupted (Likely Hung)")
