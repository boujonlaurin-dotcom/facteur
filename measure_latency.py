import time
import httpx
import asyncio

async def measure():
    url = "http://localhost:8080/api/feed" # Assuming 8080 based on logs
    async with httpx.AsyncClient() as client:
        start = time.time()
        try:
            resp = await client.get(url, timeout=10.0)
            duration = time.time() - start
            print(f"GET {url} Status: {resp.status_code}")
            print(f"Latency: {duration:.4f} seconds")
        except Exception as e:
            print(f"Error accessing {url}: {e}")

if __name__ == "__main__":
    asyncio.run(measure())
