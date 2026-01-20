#!/usr/bin/env python3
"""Check for invalid theme values in sources table."""
import asyncio
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from sqlalchemy import text
from app.database import engine

VALID_THEMES = {'tech', 'society', 'environment', 'economy', 'politics', 'culture', 'science', 'international'}

async def check_themes():
    async with engine.connect() as conn:
        result = await conn.execute(text("SELECT DISTINCT theme FROM sources"))
        themes = [row[0] for row in result.fetchall()]
        
        print("Current themes in database:")
        for theme in sorted(themes):
            status = "✓" if theme in VALID_THEMES else "✗ INVALID"
            print(f"  {status}: '{theme}'")
        
        invalid = [t for t in themes if t not in VALID_THEMES]
        if invalid:
            print(f"\n❌ Found {len(invalid)} invalid theme(s). These must be fixed before adding CHECK constraint.")
        else:
            print("\n✅ All themes are valid!")

if __name__ == "__main__":
    asyncio.run(check_themes())
