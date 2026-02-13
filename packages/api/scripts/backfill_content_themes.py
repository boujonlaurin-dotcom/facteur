"""
Backfill content.theme à partir des topics ML existants.

Pour chaque article ayant des topics classifiés mais pas de thème,
dérive le thème broad depuis topics[0] via le mapping topic→theme.

Pas de re-classification ML nécessaire : utilise les données existantes.

Usage:
    cd packages/api && source venv/bin/activate
    python scripts/backfill_content_themes.py [--batch-size=500] [--limit=0]
"""

from dotenv import load_dotenv
from pathlib import Path

# Load .env BEFORE any app imports
load_dotenv(Path(__file__).parent.parent / ".env", override=True)

import argparse
import asyncio
import os
import sys

from sqlalchemy import select, func

# Add parent directory for app imports
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.models.content import Content
from app.services.ml.topic_theme_mapper import infer_theme_from_topics


async def backfill_themes(batch_size: int = 500, limit: int = 0) -> None:
    from app.database import async_session_maker, init_db

    print("Initializing database connection...")
    await init_db()

    async with async_session_maker() as session:
        # Compter les articles à traiter
        count_query = (
            select(func.count(Content.id))
            .where(Content.topics.isnot(None), Content.theme.is_(None))
        )
        total = await session.scalar(count_query)
        print(f"Found {total} articles with topics but no theme")

        if total == 0:
            print("Nothing to backfill.")
            return

        effective_limit = limit if limit > 0 else total
        processed = 0
        themed = 0
        last_id = None

        while processed < effective_limit:
            current_batch = min(batch_size, effective_limit - processed)

            # Keyset pagination : ORDER BY id + WHERE id > last_id
            # Garantit que chaque article est visité exactement une fois,
            # même si infer_theme_from_topics retourne None (topic inconnu).
            query = (
                select(Content)
                .where(Content.topics.isnot(None), Content.theme.is_(None))
                .order_by(Content.id)
                .limit(current_batch)
            )
            if last_id is not None:
                query = query.where(Content.id > last_id)

            result = await session.execute(query)
            articles = result.scalars().all()

            if not articles:
                break

            for article in articles:
                theme = infer_theme_from_topics(article.topics)
                if theme:
                    article.theme = theme
                    themed += 1

            await session.commit()
            processed += len(articles)
            last_id = articles[-1].id
            print(f"  Processed {processed}/{effective_limit} (themed: {themed})")

        print(f"\nBackfill complete: {themed}/{processed} articles got a theme")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Backfill content.theme from existing topics")
    parser.add_argument("--batch-size", type=int, default=500)
    parser.add_argument("--limit", type=int, default=0, help="Max articles to process (0 = all)")
    args = parser.parse_args()

    asyncio.run(backfill_themes(args.batch_size, args.limit))
