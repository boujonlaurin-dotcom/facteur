import asyncio
import httpx

async def main():
    headers = {
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept-Language": "en-US,en;q=0.9",
    }
    
    urls = [
        ("youtube", "https://www.youtube.com/@ChezAnatole"),
        ("vert", "https://vert.eco/"),
    ]
    
    async with httpx.AsyncClient(headers=headers, follow_redirects=True) as client:
        for name, url in urls:
            print(f"Fetching {url}...")
            response = await client.get(url)
            filename = f"scripts/dump_{name}.html"
            with open(filename, "w") as f:
                f.write(response.text)
            print(f"Saved to {filename} ({len(response.text)} bytes)")

if __name__ == "__main__":
    asyncio.run(main())
