#!/usr/bin/env python3
"""Backfill source catalog adjustments for onboarding economy sources.

Dry-run by default. With `--apply`, this script:
  - deactivates economy sources removed from the curated catalog;
  - renames the malformed BFM import label `Home Fil actu` to `BFM`.

It preserves contents and relationships by only updating `sources`.
"""

from __future__ import annotations

import argparse
import asyncio
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.database import async_session_maker, engine


DEAD_SOURCE_SPECS = (
    {
        "name": "Les Échos",
        "url": "https://www.lesechos.fr/",
        "feed": "https://services.lesechos.fr/rss/les-echos-une.xml",
    },
    {
        "name": "Guerres de Business",
        "url": "https://wondery.com/shows/guerres-de-business/",
        "feed": "https://feeds.megaphone.fm/WWS2399238883",
    },
    {
        "name": "Alternatives Économiques",
        "url": "https://www.alternatives-economiques.fr/",
        "feed": "https://www.alternatives-economiques.fr/flux-rss",
    },
)


@dataclass(frozen=True)
class CatalogBackfillResult:
    deactivated: int
    renamed_bfm: int


async def apply_catalog_adjustments(
    session: AsyncSession,
    *,
    apply: bool = False,
) -> CatalogBackfillResult:
    deactivated = 0
    renamed_bfm = 0

    for spec in DEAD_SOURCE_SPECS:
        params = {
            "name": spec["name"],
            "url": spec["url"],
            "feed": spec["feed"],
        }
        count_sql = text(
            """
            SELECT count(*)
            FROM sources
            WHERE is_active = true
              AND (
                lower(name) = lower(:name)
                OR url = :url
                OR feed_url = :feed
              )
            """
        )
        update_sql = text(
            """
            UPDATE sources
            SET is_active = false,
                is_curated = false
            WHERE is_active = true
              AND (
                lower(name) = lower(:name)
                OR url = :url
                OR feed_url = :feed
              )
            """
        )
        if apply:
            result = await session.execute(update_sql, params)
            deactivated += result.rowcount or 0
        else:
            result = await session.execute(count_sql, params)
            deactivated += result.scalar_one()

    bfm_params = {"old_name": "Home Fil actu", "new_name": "BFM"}
    bfm_count_sql = text(
        """
        SELECT count(*)
        FROM sources
        WHERE name = :old_name
          AND (
            lower(coalesce(url, '')) LIKE '%bfmtv.com%'
            OR lower(coalesce(feed_url, '')) LIKE '%bfmtv.com%'
          )
        """
    )
    bfm_update_sql = text(
        """
        UPDATE sources
        SET name = :new_name
        WHERE name = :old_name
          AND (
            lower(coalesce(url, '')) LIKE '%bfmtv.com%'
            OR lower(coalesce(feed_url, '')) LIKE '%bfmtv.com%'
          )
        """
    )
    if apply:
        result = await session.execute(bfm_update_sql, bfm_params)
        renamed_bfm = result.rowcount or 0
        await session.commit()
    else:
        result = await session.execute(bfm_count_sql, bfm_params)
        renamed_bfm = result.scalar_one()

    return CatalogBackfillResult(
        deactivated=deactivated,
        renamed_bfm=renamed_bfm,
    )


def _is_prod_database_url(url: str | None) -> bool:
    if not url:
        return False
    lowered = url.lower()
    return "localhost" not in lowered and "127.0.0.1" not in lowered


async def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Apply DB updates")
    parser.add_argument(
        "--allow-prod",
        action="store_true",
        help="Allow --apply against a non-local DATABASE_URL",
    )
    args = parser.parse_args()

    settings = get_settings()
    if args.apply and _is_prod_database_url(settings.database_url) and not args.allow_prod:
        raise SystemExit("Refusing to apply against prod without --allow-prod")

    async with async_session_maker() as session:
        result = await apply_catalog_adjustments(session, apply=args.apply)

    mode = "applied" if args.apply else "dry-run"
    print(
        f"{mode}: deactivated={result.deactivated}, "
        f"renamed_bfm={result.renamed_bfm}"
    )
    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
