import asyncio
import csv
import httpx
import re
import os
import sys
from typing import Optional, List

# Add parent directory to path to allow imports from app
sys.path.append(os.path.join(os.getcwd(), "packages/api"))

async def detect_site_feed(url: str, client: httpx.AsyncClient) -> Optional[str]:
    try:
        headers = {"User-Agent": "Mozilla/5.0"}
        response = await client.get(url, follow_redirects=True, headers=headers, timeout=10.0)
        if response.status_code == 200:
            patterns = [
                r'<link[^>]+type="application/rss\+xml"[^>]+href="([^"]+)"',
                r'<link[^>]+type="application/atom\+xml"[^>]+href="([^"]+)"'
            ]
            for pattern in patterns:
                match = re.search(pattern, response.text)
                if match:
                    feed_url = match.group(1)
                    if not feed_url.startswith("http"):
                        from urllib.parse import urljoin
                        feed_url = urljoin(url, feed_url)
                    return feed_url
    except Exception as e:
        return f"ERROR: {str(e)}"
    return None

async def main():
    csv_path = "sources/sources_candidates.csv"
    if not os.path.exists(csv_path):
        print(f"CSV not found: {csv_path}")
        return

    with open(csv_path, mode='r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    print(f"Checking {len(rows)} sources...")
    
    async with httpx.AsyncClient() as client:
        tasks = []
        for row in rows[:50]: # Check first 50 as a sample
            tasks.append(check_source(row, client))
        
        results = await asyncio.gather(*tasks)
        
    failures = [r for r in results if r['status'] != 'OK']
    print(f"\nFound {len(failures)} failures in first 50 rows:")
    for f in failures:
        print(f"- {f['name']}: {f['reason']} ({f['url']})")

async def check_source(row, client):
    name = row.get("Name")
    url = row.get("URL")
    res = await detect_site_feed(url, client)
    if res and not res.startswith("ERROR"):
        return {"name": name, "status": "OK", "url": url}
    else:
        return {"name": name, "status": "FAIL", "reason": res or "No feed link found", "url": url}

if __name__ == "__main__":
    asyncio.run(main())
