#!/usr/bin/env python3
"""Seed du référentiel `media_eval_medias` — 2 médias pilotes V0.

Upsert par ``domaine`` (insert si absent, update des champs référentiel
sinon). **Dry-run par défaut**, ``--apply`` gardé (``--allow-prod`` requis
hors DB test — pattern `apply_source_evaluations.py`). Idempotent.

Usage :
    cd packages/api
    python3 scripts/media_eval/seed_medias.py                    # dry-run
    python3 scripts/media_eval/seed_medias.py --apply            # DB test
    python3 scripts/media_eval/seed_medias.py --apply --allow-prod
"""

from __future__ import annotations

import argparse
import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from sqlalchemy import select

from app.config import get_settings
from app.database import async_session_maker, engine
from app.models.media_eval import MediaEvalMedia, TypeMedia
from scripts.cleanup_orphan_sources import _is_test_db

# Référentiel V0 (décisions PO 07/07/2026). Convention CNEWS : le média évalué
# est le domaine cnews.fr, type audiovisuel → signaux ARCOM applicables.
MEDIAS_PILOTES: list[dict] = [
    {
        "nom": "CNEWS",
        "domaine": "cnews.fr",
        "type_media": TypeMedia.AUDIOVISUEL,
        "paywall": False,
        "rubriques_opinion": ["opinions"],
        "volume_articles_jour": 80,
    },
    {
        "nom": "Reporterre",
        "domaine": "reporterre.net",
        "type_media": TypeMedia.PRESSE_EN_LIGNE,
        "paywall": False,
        "rubriques_opinion": ["tribunes", "chroniques"],
        "volume_articles_jour": 12,
    },
]

_CHAMPS = (
    "nom",
    "type_media",
    "paywall",
    "rubriques_opinion",
    "volume_articles_jour",
)


async def seed(session, medias: list[dict]) -> tuple[list[str], list[str]]:
    """Upsert par domaine. Retourne (créés, mis à jour) — sans commit."""
    crees: list[str] = []
    maj: list[str] = []
    for spec in medias:
        existant = (
            await session.execute(
                select(MediaEvalMedia).where(MediaEvalMedia.domaine == spec["domaine"])
            )
        ).scalar_one_or_none()
        if existant is None:
            session.add(MediaEvalMedia(**spec))
            crees.append(spec["domaine"])
            continue
        change = False
        for champ in _CHAMPS:
            if getattr(existant, champ) != spec[champ]:
                setattr(existant, champ, spec[champ])
                change = True
        if change:
            maj.append(spec["domaine"])
    return crees, maj


async def run(apply: bool, allow_prod: bool) -> int:
    settings = get_settings()
    db_url = settings.database_url or ""
    is_test = _is_test_db(db_url)
    print(
        f"DB cible : {db_url.split('@')[-1] if '@' in db_url else db_url}  (test={is_test})"
    )
    if apply and not is_test and not allow_prod:
        print("\nABORT : --apply contre une DB non-test sans --allow-prod (gated PO).")
        return 2

    async with async_session_maker() as session:
        try:
            crees, maj = await seed(session, MEDIAS_PILOTES)
            print(f"À créer : {crees or '-'} | à mettre à jour : {maj or '-'}")
            if not apply:
                await session.rollback()
                print("(dry-run — aucune mutation. Relance avec --apply.)")
                return 0
            await session.commit()
            print(f"APPLIQUÉ : {len(crees)} créés, {len(maj)} mis à jour.")
            return 0
        except Exception:
            await session.rollback()
            raise
        finally:
            await engine.dispose()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--apply", action="store_true", help="exécute (défaut: dry-run)"
    )
    parser.add_argument(
        "--allow-prod", action="store_true", help="autorise --apply en prod"
    )
    args = parser.parse_args()
    sys.exit(asyncio.run(run(apply=args.apply, allow_prod=args.allow_prod)))


if __name__ == "__main__":
    main()
