"""Recalcul périodique de `Source.coverage_themes` (couverture éditoriale 90j).

Tourne 1×/semaine. Pour chaque source ayant un volume suffisant de Content
**classifiés** (`theme IS NOT NULL`) sur 90 jours, dérive le top des thèmes
réellement couverts (hors thème primaire) à partir du volume publié. Sert la
**découverte** (recall large : « étoffer un thème », catalogue par thème) —
jamais le scoring, qui garde `secondary_themes` (précis, curé). Cf. story 22.5.

⚠️ Dépendance à la classification ML (hand-off B) : `content.theme` n'existe
que sur le contenu 7-90j (0 % à < 7j tant que la classif est en retard). D'où
la fenêtre **90j** (une fenêtre courte ne capterait quasiment rien). Si la
classif reste morte, le corpus thémé vieillit et sort de la fenêtre → la
dérivation se dégrade. Réparer la classif est le vrai levier.

Idempotent : ne réécrit une source que si son set dérivé change ; une source
sous le seuil de volume est **laissée intacte** (jamais reset à NULL — on ne
churn pas les low-volume). N'écrit QUE `coverage_themes` (jamais
`secondary_themes`, jamais `Source.theme`).
"""

from __future__ import annotations

from collections import Counter
from datetime import UTC, datetime, timedelta

import structlog
from sqlalchemy import bindparam, text

from app.database import safe_async_session

logger = structlog.get_logger()

# Fenêtre d'observation. 90j impératif : à cause du lag de classification,
# `content.theme` n'existe QUE sur 7-90j — une fenêtre courte (≤20j) ne
# capterait quasiment que la bande 7-20j. Cf. docstring module.
_WINDOW_DAYS = 90

# Volume minimum de Content classifiés / 90j pour dériver quoi que ce soit.
# En-dessous → source laissée intacte (pas de reset, pas de dérivation sur un
# échantillon fragile).
_MIN_SOURCE_VOLUME = 30

# Gate par thème : on garde un thème si sa part ≥ _MIN_PART OU son volume
# absolu ≥ _MIN_COUNT (un thème très présent en absolu compte même si la
# source est un généraliste à longue traîne).
_MIN_PART = 0.15
_MIN_COUNT = 8

# Nombre max de thèmes de couverture retenus par source (top par volume).
_TOP_N = 5


async def recompute_source_coverage_themes() -> dict[str, int]:
    """Recalcule `sources.coverage_themes` depuis les Content des 90 derniers jours.

    Renvoie un dict de stats pour les logs (sources mises à jour, inchangées,
    laissées intactes faute de volume, total examiné).
    """
    cutoff = datetime.now(UTC) - timedelta(days=_WINDOW_DAYS)

    updated = 0
    unchanged = 0
    skipped_low_volume = 0

    async with safe_async_session() as session:
        # Compteurs (source_id, theme) sur la fenêtre, contenus classifiés
        # seulement. On NE réutilise PAS `_aggregate_source_themes` de
        # sources.py (il replie la traîne en ligne "autres" hors taxonomie et
        # tronque au top-6) : ici on veut le volume brut par thème.
        rows = (
            await session.execute(
                text(
                    "SELECT source_id, theme, COUNT(*) AS n "
                    "FROM contents "
                    "WHERE theme IS NOT NULL "
                    "  AND published_at >= :cutoff "
                    "GROUP BY source_id, theme"
                ),
                {"cutoff": cutoff},
            )
        ).fetchall()

        by_source: dict[str, Counter[str]] = {}
        for row in rows:
            by_source.setdefault(str(row.source_id), Counter())[row.theme] = row.n

        # Thème primaire de chaque source (exclu de la couverture).
        primary_by_id: dict[str, str] = {}
        if by_source:
            primary_stmt = text(
                "SELECT id::text AS id, theme FROM sources WHERE id::text IN :ids"
            ).bindparams(bindparam("ids", expanding=True))
            primary_rows = (
                await session.execute(primary_stmt, {"ids": list(by_source)})
            ).fetchall()
            primary_by_id = {r.id: r.theme for r in primary_rows}

        # Dérivation : gate part/count → exclure primaire → top-N par volume.
        verdicts: dict[str, list[str]] = {}
        for source_id, counter in by_source.items():
            total = sum(counter.values())
            if total < _MIN_SOURCE_VOLUME:
                skipped_low_volume += 1
                continue
            primary = primary_by_id.get(source_id)
            kept = [
                (theme, n)
                for theme, n in counter.items()
                if theme != primary and (n / total >= _MIN_PART or n >= _MIN_COUNT)
            ]
            kept.sort(key=lambda tn: tn[1], reverse=True)
            verdicts[source_id] = [theme for theme, _ in kept[:_TOP_N]]

        if not verdicts:
            stats = {
                "sources_updated": 0,
                "sources_unchanged": 0,
                "sources_skipped_low_volume": skipped_low_volume,
                "total_examined": len(by_source),
            }
            logger.info("recompute_source_coverage_themes_done", **stats)
            return stats

        lookup_stmt = text(
            "SELECT id::text AS id, coverage_themes FROM sources WHERE id::text IN :ids"
        ).bindparams(bindparam("ids", expanding=True))
        current_rows = (
            await session.execute(lookup_stmt, {"ids": list(verdicts)})
        ).fetchall()
        current_by_id = {r.id: (r.coverage_themes or []) for r in current_rows}

        params: list[dict[str, object]] = []
        for source_id, themes in verdicts.items():
            if list(current_by_id.get(source_id, [])) == themes:
                unchanged += 1
                continue
            params.append({"id": source_id, "themes": themes})
            updated += 1

        if params:
            await session.execute(
                text("UPDATE sources SET coverage_themes = :themes WHERE id = :id"),
                params,
            )

        await session.commit()

    stats = {
        "sources_updated": updated,
        "sources_unchanged": unchanged,
        "sources_skipped_low_volume": skipped_low_volume,
        "total_examined": len(by_source),
    }
    logger.info("recompute_source_coverage_themes_done", **stats)
    return stats
