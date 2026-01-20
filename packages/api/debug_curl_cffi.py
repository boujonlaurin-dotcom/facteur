
import asyncio
from curl_cffi.requests import AsyncSession

URLS = [
    # AP News
    "https://apnews.com/index.rss", 
    "https://apnews.com/rss",
    # Libération
    "https://www.liberation.fr/rss/",
    "https://www.liberation.fr/arc/outboundfeeds/rss-all/",
    # Commentaire
    "https://www.commentaire.fr/feed/",
]

async def test():
    print("--- Testing curl_cffi configurations ---")
    
    browsers = ["chrome", "safari", "edge"]
    
    for url in URLS:
        print(f"\nTarget: {url}")
        for browser in browsers:
            print(f"  Browser: {browser}")
            try:
                async with AsyncSession(impersonate=browser) as s:
                    r = await s.get(url, allow_redirects=True)
                    print(f"    Status: {r.status_code}")
                    if r.status_code != 200:
                        print(f"    Body preview: {r.text[:200]}")
            except Exception as e:
                print(f"    Error: {e}")

if __name__ == "__main__":
    asyncio.run(test())
