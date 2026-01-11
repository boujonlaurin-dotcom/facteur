#!/usr/bin/env python3
"""
Script d'import des sources curées depuis sources.csv.

Usage:
    python scripts/import_sources.py
"""

import asyncio
import csv
import sys
from pathlib import Path
from uuid import uuid4

# Ajouter le path du package api
sys.path.insert(0, str(Path(__file__).parent.parent / "packages" / "api"))

from sqlalchemy import select
from app.database import async_session_maker, init_db
from app.models.source import Source


# Mapping des thèmes CSV vers les slugs
THEME_MAPPING = {
    "Société & Climat": "society_climate",
    "Économie": "economy",
    "Géopolitique": "geopolitics",
    "Tech & Futur": "tech",
    "Culture & Idées": "culture_ideas",
}

# Mapping des types
TYPE_MAPPING = {
    "Podcast": "podcast",
    "YouTube": "youtube",
    "Site": "article",
    "RSS": "article",
    "Newsletter": "article",
}


async def import_sources():
    """Importe les sources depuis le fichier CSV."""
    csv_path = Path(__file__).parent.parent / "sources" / "sources.csv"

    if not csv_path.exists():
        print(f"❌ Fichier non trouvé: {csv_path}")
        return

    print(f"📂 Lecture de {csv_path}")

    await init_db()

    async with async_session_maker() as db:
        # Lire le CSV
        with open(csv_path, newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            sources = list(reader)

        print(f"📊 {len(sources)} sources trouvées")

        imported = 0
        skipped = 0

        for row in sources:
            name = row["Name"]
            url = row["URL"]
            source_type = TYPE_MAPPING.get(row["Type"], "article")
            theme = THEME_MAPPING.get(row["Thème"], "culture_ideas")

            # Vérifier si la source existe déjà
            existing = await db.execute(
                select(Source).where(Source.url == url)
            )
            if existing.scalar_one_or_none():
                print(f"  ⏭️  {name} (existe déjà)")
                skipped += 1
                continue

            # Créer la source
            # Note: feed_url devra être configuré manuellement ou via détection
            source = Source(
                id=uuid4(),
                name=name,
                url=url,
                feed_url=url,  # À ajuster selon le type
                type=source_type,
                theme=theme,
                description=row.get("Rationale", ""),
                is_curated=True,
                is_active=True,
            )
            db.add(source)
            imported += 1
            print(f"  ✅ {name}")

        await db.commit()

        print(f"\n🎉 Import terminé!")
        print(f"   - Importées: {imported}")
        print(f"   - Ignorées: {skipped}")


if __name__ == "__main__":
    asyncio.run(import_sources())

