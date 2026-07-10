#!/usr/bin/env python3
"""Correction ponctuelle : `sources.theme` de « Basket USA » (tech -> sport).

Contexte : 3 articles NBA de la source **Basket USA** sont apparus sous le
thème « Technologie » dans le feed thématique (2026-07-10). Root cause = donnée
fausse `sources.theme = 'tech'`, produite par le bug de sous-chaîne de
`SourceService._guess_theme()` (« ia » matchant dans « média », égalité de score
tie-breakée arbitrairement sur `tech`). Le fix code du heuristique est livré dans
la même PR ; ce script corrige la **donnée déjà écrite** (DML pure, colonne
existante, **pas de migration** Alembic nécessaire, insensible au drift).

Garde-fous (calqués sur `apply_source_reclassification.py`) :
  - **Dry-run par défaut** ; `--apply` gardé (`--allow-prod` requis en prod).
  - **Idempotent** : re-run sans changement = no-op.
  - Audit : imprime les autres sources au thème `tech` (relecture nom+desc à la
    main pour repérer d'autres cas mal rangés type sport), **sans les muter**.

Usage :
    cd packages/api
    python3 scripts/fix_basket_usa_theme.py                       # dry-run + audit
    python3 scripts/fix_basket_usa_theme.py --apply --allow-prod   # prod (gated PO)
"""

from __future__ import annotations

import argparse
import asyncio
import sys
from pathlib import Path
from uuid import UUID

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import select, update

from app.config import get_settings
from app.database import async_session_maker, engine
from app.models.source import Source
from scripts.cleanup_orphan_sources import _is_test_db

BASKET_USA_ID = "6e27afbc-92ec-4450-82cf-58d106e2ebe5"
TARGET_THEME = "sport"


async def _audit_tech_sources(session) -> None:
    """Imprime les sources au thème `tech` pour relecture manuelle (non muté)."""
    result = await session.execute(
        select(Source.id, Source.name, Source.description)
        .where(Source.theme == "tech")
        .order_by(Source.name)
    )
    rows = list(result)
    print("-" * 78)
    print(f"AUDIT : {len(rows)} source(s) au thème 'tech' (relecture manuelle) :")
    for r in rows:
        desc = (r.description or "").replace("\n", " ")
        print(f"  • {r.name} ({r.id})")
        print(f"      {desc[:140]}")
    print("-" * 78)


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
            result = await session.execute(
                select(Source.id, Source.name, Source.theme).where(
                    Source.id == UUID(BASKET_USA_ID)
                )
            )
            row = result.first()
            if row is None:
                print(f"\nABORT : source introuvable ({BASKET_USA_ID}).")
                return 2

            print(f"\nCible : {row.name} ({row.id})")
            print(f"  theme : {row.theme} -> {TARGET_THEME}")

            await _audit_tech_sources(session)

            if row.theme == TARGET_THEME:
                print("\n(no-op — déjà au bon thème.)")
                return 0

            if not apply:
                print("\n(dry-run — aucune mutation. Relance avec --apply.)")
                return 0

            await session.execute(
                update(Source)
                .where(Source.id == UUID(BASKET_USA_ID))
                .values(theme=TARGET_THEME)
            )
            await session.commit()
            print(f"\nAPPLIQUÉ : theme -> {TARGET_THEME}.")
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
