"""
Populate secondary_themes pour les sources généralistes.

Les sources comme Le Monde (thème principal: international) publient
des articles tech, politique, économie, etc. Ce script assigne des
thèmes secondaires pour améliorer la diversité du feed.

Usage:
    cd packages/api && source venv/bin/activate
    python scripts/populate_secondary_themes.py
"""

from dotenv import load_dotenv
from pathlib import Path

# Load .env BEFORE any app imports
load_dotenv(Path(__file__).parent.parent / ".env", override=True)

import asyncio
import os
import sys

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

# Add parent directory for app imports
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.models.source import Source


# Mapping source_name → secondary_themes
# Basé sur la couverture éditoriale réelle de chaque source
SECONDARY_THEMES: dict[str, list[str]] = {
    # Généralistes internationaux
    "Le Monde": ["society", "politics", "economy", "culture", "tech", "science"],
    "Le Figaro": ["society", "politics", "economy"],
    "Courrier International": ["society", "economy", "culture", "tech"],
    "Le Monde Diplomatique": ["economy", "politics"],
    # Généralistes société
    "France Info": ["politics", "economy", "international", "environment"],
    "France Inter": ["culture", "politics", "science"],
    "RTL": ["politics", "economy"],
    "Europe 1": ["politics", "economy"],
    "Libération": ["culture", "politics", "international"],
    "Le Point": ["politics", "economy", "international"],
    "Mediapart": ["politics", "economy", "international"],
    "La Croix": ["politics", "culture", "international"],
    "Ouest-France": ["politics", "economy", "environment"],
    # Économie
    "Les Echos": ["tech", "politics", "international"],
    "Alternatives Économiques": ["society", "environment", "politics"],
    # Politique
    "Politico": ["economy", "tech", "international"],
    # Tech
    "Socialter": ["environment", "society", "economy"],
    # Culture
    "The Conversation": ["science", "society", "environment"],
    # Environnement
    "Bon Pote": ["science", "society"],
    "Reporterre": ["society", "politics", "science"],
}


async def main() -> None:
    from app.database import async_session_maker, init_db

    print("Initializing database connection...")
    await init_db()

    async with async_session_maker() as session:
        updated = 0
        not_found = []

        for source_name, themes in SECONDARY_THEMES.items():
            result = await session.execute(
                select(Source).where(Source.name == source_name)
            )
            source = result.scalar_one_or_none()

            if source:
                source.secondary_themes = themes
                updated += 1
                print(f"  {source_name}: {themes}")
            else:
                not_found.append(source_name)
                print(f"  {source_name}: NOT FOUND")

        await session.commit()

        print(f"\nUpdated: {updated}/{len(SECONDARY_THEMES)}")
        if not_found:
            print(f"Not found: {', '.join(not_found)}")


if __name__ == "__main__":
    asyncio.run(main())
