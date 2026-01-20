import asyncio
import os
import sys
from typing import Set

from dotenv import load_dotenv
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

# Add parent directory to path to allow imports from app
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.models.source import Source
from app.database import async_session_maker, init_db

# Load .env
load_dotenv(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".env"))

# --- TAXONOMY CONSTANTS (From PRD) ---

VALID_THEMES: Set[str] = {
    "tech", "society", "environment", "economy", "politics", 
    "culture", "science", "international"
}

VALID_TOPICS: Set[str] = {
    # tech (12)
    "ai", "llm", "crypto", "web3", "space", "biotech", "quantum", "cybersecurity", "robotics", "gaming", "cleantech", "data-privacy",
    # society (10)
    "social-justice", "feminism", "lgbtq", "immigration", "health", "education", "urbanism", "housing", "work-reform", "justice-system",
    # environment (8)
    "climate", "biodiversity", "energy-transition", "pollution", "circular-economy", "agriculture", "oceans", "forests",
    # economy (8)
    "macro", "finance", "startups", "venture-capital", "labor-market", "inflation", "trade", "taxation",
    # politics (5)
    "elections", "institutions", "local-politics", "activism", "democracy",
    # culture (4)
    "philosophy", "art", "cinema", "media-critics",
    # science (2)
    "fundamental-research", "applied-science",
    # international (1)
    "geopolitics"
}

async def validate_taxonomy():
    print("🔍 Starting Taxonomy Validation...")
    
    await init_db()
    
    async with async_session_maker() as session:
        # 1. Check Source Themes
        print("\n--- 1. Checking Source Themes ---")
        result = await session.execute(select(Source))
        sources = result.scalars().all()
        
        invalid_themes_count = 0
        for source in sources:
            if source.theme not in VALID_THEMES:
                print(f"❌ Invalid theme '{source.theme}' for source: {source.name} (ID: {source.id})")
                invalid_themes_count += 1
        
        if invalid_themes_count == 0:
            print("✅ All source themes are valid.")
        else:
            print(f"❌ Found {invalid_themes_count} sources with invalid themes.")

        # 2. Check Granular Topics
        print("\n--- 2. Checking Granular Topics ---")
        invalid_topics_count = 0
        sources_with_topics = [s for s in sources if s.granular_topics]
        
        for source in sources_with_topics:
            for topic in source.granular_topics:
                if topic not in VALID_TOPICS:
                    print(f"❌ Invalid topic '{topic}' in source: {source.name} (ID: {source.id})")
                    invalid_topics_count += 1
        
        if invalid_topics_count == 0:
            print(f"✅ All granular topics ({len(sources_with_topics)} sources) are valid.")
        else:
            print(f"❌ Found {invalid_topics_count} invalid topics across sources.")

        # 3. Coverage Check (CURATED sources)
        print("\n--- 3. Coverage Check (CURATED) ---")
        curated_sources = [s for s in sources if s.is_curated]
        total_curated = len(curated_sources)
        curated_with_topics = [s for s in curated_sources if s.granular_topics and len(s.granular_topics) > 0]
        
        coverage = (len(curated_with_topics) / total_curated * 100) if total_curated > 0 else 0
        
        print(f"📊 Curated Sources: {total_curated}")
        print(f"📊 Curated with Topics: {len(curated_with_topics)}")
        print(f"📊 Coverage: {coverage:.2f}%")
        
        if coverage >= 95.0:
            print(f"✅ Coverage target (≥95%) met!")
        else:
            print(f"⚠️ Coverage target (95%) NOT met. Please enrich curated sources.")
            # List curated sources missing topics
            missing = [s.name for s in curated_sources if s not in curated_with_topics]
            print(f"🔎 Missing topics for: {', '.join(missing)}")

        # Summary
        print("\n--- Final Summary ---")
        if invalid_themes_count == 0 and invalid_topics_count == 0 and coverage >= 95.0:
            print("🚀 TAXONOMY INTEGRITY: 100% VALID")
            return True
        else:
            print("🚨 TAXONOMY INTEGRITY: ISSUES DETECTED")
            return False

if __name__ == "__main__":
    success = asyncio.run(validate_taxonomy())
    if not success:
        sys.exit(1)
