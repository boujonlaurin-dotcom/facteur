#!/usr/bin/env python3
"""Extraction des cibles d'évaluation de sources (Composant 1, étape 1a).

**Read-only.** Produit `.context/source_eval_targets.json` :
  - `targets` : sources actives, content>0, `bias_stance='unknown'` OU
    `description IS NULL` — MOINS le junk et les perdants de fusion
    (réutilise `cleanup_orphan_sources.build_plan` -> respecte l'ordre
    « nettoyage avant éval » sans avoir à appliquer le nettoyage d'abord).
  - `gold` : sources curées avec vraie éval (`bias_origin='curated'` ∧
    `bias_stance<>'unknown'`, actives, content>0) — sert au benchmark 1c.

Chaque entrée porte le contexte : `name, url, feed_url, theme, type,
source_tier` + un échantillon des derniers titres d'articles (pour situer
la ligne éditoriale sans deviner).

Usage : cd packages/api && python3 scripts/export_source_eval_targets.py
"""

from __future__ import annotations

import asyncio
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import text

from app.database import async_session_maker, engine
from scripts.cleanup_orphan_sources import build_plan, gather_stats

TITLE_SAMPLE = 15


async def _recent_titles(session, source_ids: list, limit: int) -> dict[str, list[str]]:
    if not source_ids:
        return {}
    result = await session.execute(
        text(
            """
            SELECT source_id, title FROM (
              SELECT source_id, title,
                     row_number() OVER (
                       PARTITION BY source_id ORDER BY published_at DESC
                     ) AS rn
              FROM contents WHERE source_id = ANY(:ids)
            ) t WHERE rn <= :limit
            """
        ),
        {"ids": source_ids, "limit": limit},
    )
    out: dict[str, list[str]] = {}
    for m in result.mappings():
        out.setdefault(str(m["source_id"]), []).append(m["title"])
    return out


def _context(row, titles: dict[str, list[str]]) -> dict:
    sid = str(row.id)
    return {
        "source_id": sid,
        "name": row.name,
        "url": row.url,
        "feed_url": row.feed_url,
        "type": row.type,
        "theme": row.theme,
        "n_content": row.n_content,
        "recent_titles": titles.get(sid, []),
        # éval actuelle (pour le diff / le gold)
        "current": {
            "bias_stance": row.bias_stance,
            "reliability_score": row.reliability_score,
            "bias_origin": row.bias_origin,
            "description": row.description,
            "score_independence": row.score_independence,
            "score_rigor": row.score_rigor,
            "score_ux": row.score_ux,
        },
    }


async def export() -> dict:
    async with async_session_maker() as session:
        rows = await gather_stats(
            session
        )  # inclut source_tier ? non -> theme/type suffisent
        plan = build_plan(rows)
        excluded = set(plan.deleted_ids)  # junk + dead + perdants de fusion

        targets, gold = [], []
        for r in rows.values():
            if r.id in excluded:
                continue
            is_target = (
                r.is_active
                and r.n_content > 0
                and (r.bias_stance == "unknown" or r.description is None)
            )
            is_gold = (
                r.is_active
                and r.n_content > 0
                and r.bias_origin == "curated"
                and r.bias_stance != "unknown"
            )
            if is_target:
                targets.append(r)
            elif is_gold:
                gold.append(r)

        all_ids = [r.id for r in targets] + [r.id for r in gold]
        titles = await _recent_titles(session, all_ids, TITLE_SAMPLE)

        await engine.dispose()
        return {
            "targets": [_context(r, titles) for r in targets],
            "gold": [_context(r, titles) for r in gold],
        }


async def main() -> None:
    data = await export()
    out = Path(__file__).resolve().parents[3] / ".context" / "source_eval_targets.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(data, indent=2, ensure_ascii=False))
    print(f"Écrit {out}")
    print(f"  targets : {len(data['targets'])}")
    print(f"  gold    : {len(data['gold'])}")


if __name__ == "__main__":
    asyncio.run(main())
