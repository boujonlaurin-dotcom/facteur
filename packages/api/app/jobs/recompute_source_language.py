"""Recalcul périodique de `Source.language` (langue majoritaire).

Tourne 1×/jour. Pour chaque source ayant ≥1 Content à langue connue dans
les 30 derniers jours, on calcule la langue majoritaire (seuil 60%). Les
sources sans échantillon suffisant restent à `NULL` — traité comme FR par
défaut côté curation (rétro-compat — cf. language_user_filter.py).

Aligné avec le backfill initial de la migration `lg02` : un seul endroit
décrit la règle, pas de drift entre cold-start et runtime.
"""

from __future__ import annotations

from collections import Counter
from datetime import UTC, datetime, timedelta

import structlog
from sqlalchemy import bindparam, text

from app.database import safe_async_session

logger = structlog.get_logger()

# Seuil de majorité (sur l'échantillon des contents à langue connue).
# Sous le seuil → on remet à NULL pour éviter de figer un fragile 51/49.
_MAJORITY_THRESHOLD = 0.60

# Fenêtre d'observation. Trop court (≤7j) → sensible aux pics de syndication
# anglaise ; trop long (≥90j) → on rate les sources qui pivotent FR↔EN.
_WINDOW_DAYS = 30


async def recompute_source_language() -> dict[str, int]:
    """Recalcule `sources.language` à partir des Content des 30 derniers jours.

    Renvoie un dict de stats pour les logs (sources mises à jour, sources
    sans signal suffisant, total examiné).
    """
    cutoff = datetime.now(UTC) - timedelta(days=_WINDOW_DAYS)

    updated = 0
    unchanged = 0
    reset_to_null = 0

    async with safe_async_session() as session:
        # Compteurs par (source_id, language) sur la fenêtre. Le tri par
        # COUNT desc nous donne directement la langue majoritaire au LIMIT 1
        # côté Python (cf. boucle plus bas).
        rows = (
            await session.execute(
                text(
                    "SELECT source_id, language, COUNT(*) AS n "
                    "FROM contents "
                    "WHERE language IS NOT NULL "
                    "  AND published_at >= :cutoff "
                    "GROUP BY source_id, language"
                ),
                {"cutoff": cutoff},
            )
        ).fetchall()

        by_source: dict[str, Counter[str]] = {}
        for row in rows:
            by_source.setdefault(str(row.source_id), Counter())[row.language] = row.n

        verdicts: dict[str, str | None] = {}
        for source_id, counter in by_source.items():
            total = sum(counter.values())
            if total == 0:
                continue
            lang, n = counter.most_common(1)[0]
            verdicts[source_id] = lang if (n / total) >= _MAJORITY_THRESHOLD else None

        if not verdicts:
            stats = {
                "sources_updated": 0,
                "sources_unchanged": 0,
                "sources_reset_to_null": 0,
                "total_examined": 0,
            }
            logger.info("recompute_source_language_done", **stats)
            return stats

        lookup_stmt = text(
            "SELECT id::text AS id, language FROM sources WHERE id::text IN :ids"
        ).bindparams(bindparam("ids", expanding=True))
        current_rows = (
            await session.execute(lookup_stmt, {"ids": list(verdicts)})
        ).fetchall()
        current_by_id = {r.id: r.language for r in current_rows}

        params: list[dict[str, str | None]] = []
        for source_id, verdict in verdicts.items():
            if current_by_id.get(source_id) == verdict:
                unchanged += 1
                continue
            params.append({"id": source_id, "lang": verdict})
            if verdict is None:
                reset_to_null += 1
            else:
                updated += 1

        if params:
            await session.execute(
                text("UPDATE sources SET language = :lang WHERE id = :id"),
                params,
            )

        await session.commit()

    stats = {
        "sources_updated": updated,
        "sources_unchanged": unchanged,
        "sources_reset_to_null": reset_to_null,
        "total_examined": len(by_source),
    }
    logger.info("recompute_source_language_done", **stats)
    return stats
