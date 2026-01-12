"""Test perspective service with real article title."""

import asyncio
import sys
import os
import time

sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from app.services.perspective_service import PerspectiveService


async def test_perspective_service():
    service = PerspectiveService()
    
    # Test with a real article title from our database
    test_titles = [
        "Trump et le Venezuela : le pétro-impérialisme au grand jour",
        "Le coût politique d'une invasion du Groenland pour Trump",
        "Face à la généralisation de l'IA, faut-il appuyer sur pause ?",
    ]
    
    for title in test_titles:
        print(f"\n📰 Article: {title[:50]}...")
        print("-" * 60)
        
        # Extract keywords
        keywords = service.extract_keywords(title)
        print(f"🔑 Keywords: {keywords}")
        
        # Time the search
        start = time.time()
        perspectives = await service.search_perspectives(keywords)
        elapsed = time.time() - start
        
        print(f"⏱️  Latency: {elapsed*1000:.0f}ms")
        print(f"📊 Found {len(perspectives)} perspectives:\n")
        
        for p in perspectives:
            bias_emoji = {
                "left": "🔴",
                "center-left": "🟠",
                "center": "🟣",
                "center-right": "🔵",
                "right": "🔷",
                "unknown": "⚪"
            }.get(p.bias_stance, "⚪")
            
            print(f"  {bias_emoji} [{p.bias_stance:^12}] {p.source_name}")
            print(f"     {p.title[:55]}...")
            print()
        
        print("=" * 60)


if __name__ == "__main__":
    asyncio.run(test_perspective_service())
