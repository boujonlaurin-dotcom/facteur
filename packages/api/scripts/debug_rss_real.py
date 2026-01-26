import asyncio
import structlog
from app.services.rss_parser import RSSParser

# Configure logging to print to console
structlog.configure(
    processors=[
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.dev.ConsoleRenderer()
    ]
)

async def main():
    parser = RSSParser()
    
    urls = [
        "https://www.youtube.com/@ChezAnatole",
        "https://www.youtube.com/@Underscore_",
        "https://vert.eco/",
        "https://www.leparisien.fr/",
        "https://www.lemonde.fr/"
    ]
    
    print("\n🔍 STARTING DEBUG SESSION\n")
    
    for url in urls:
        print(f"👉 Testing: {url}")
        try:
            # We use the internal detect method directly
            # Note: We need to bypass the SourceService logic for now to test the Parser purely
            # But wait, YouTube logic is split between SourceService and RSSParser in the implementation?
            # Let's check how SourceService uses it.
            
            # Actually, SourceService calls detect_source which checks youtube first via utils, THEN calls parser.detect
            # so we should probably test RSSParser.detect() directly for websites, 
            # and check if we need to replicate SourceService logic for YouTube.
            
            # Let's just call parser.detect() first as that's what `SourceService` falls back to for websites.
            result = await parser.detect(url)
            print(f"✅ SUCCESS: Found {result.title} ({result.feed_url}) - Type: {result.feed_type}")
            print(f"   Entries: {len(result.entries)}")
        except Exception as e:
            print(f"❌ FAILED: {str(e)}")
        
        print("-" * 50)
            
    await parser.close()

if __name__ == "__main__":
    asyncio.run(main())
