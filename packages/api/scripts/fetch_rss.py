import sys
import asyncio
from curl_cffi.requests import AsyncSession

# Standard headers to resemble a browser
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8",
    "Accept-Language": "fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7",
}

async def fetch(url: str):
    # impersonate="chrome" picks the latest available chrome version
    async with AsyncSession(impersonate="chrome", headers=HEADERS, timeout=30) as s:
        try:
            response = await s.get(url)
            
            if response.status_code >= 400:
                # Output error to stderr so it doesn't pollute stdout (which is the result)
                print(f"HTTP Error {response.status_code} for {url}", file=sys.stderr)
                sys.exit(1)
            
            # Print the content to stdout.
            # Using sys.stdout.write to avoid adding extra newlines if not needed, 
            # though print is usually fine for text content.
            # We explicitly handle encoding to avoid UnicodeEncodeError in some terminals if piped.
            sys.stdout.reconfigure(encoding='utf-8')
            print(response.text)
            
        except Exception as e:
            print(f"Error fetching {url}: {e}", file=sys.stderr)
            sys.exit(1)

def main():
    if len(sys.argv) < 2:
        print("Usage: python fetch_rss.py <url>", file=sys.stderr)
        sys.exit(1)
    
    url = sys.argv[1]
    
    try:
        asyncio.run(fetch(url))
    except KeyboardInterrupt:
        sys.exit(1)
    except Exception as e:
        print(f"Critical error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
