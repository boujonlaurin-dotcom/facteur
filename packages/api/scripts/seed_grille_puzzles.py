"""Seed des puzzles de « La Grille du jour » (Story 24.1).

Exécution manuelle / one-off. La logique d'upsert vit dans
`app.services.grille_seed.seed_puzzles` (réutilisée au démarrage de l'app —
cf. docs/bugs/bug-grille-du-jour-crash.md) ; ce script ne fait que l'invoquer
sur une session dédiée et committer.

Usage :
  cd packages/api && source venv/bin/activate
  python -m scripts.seed_grille_puzzles
"""

import asyncio

from app.database import async_session_maker
from app.services.grille_seed import seed_puzzles


async def main() -> None:
    async with async_session_maker() as db:
        created, updated = await seed_puzzles(db)
        await db.commit()
    print(f"Done. {created} créés, {updated} mis à jour.")


if __name__ == "__main__":
    asyncio.run(main())
