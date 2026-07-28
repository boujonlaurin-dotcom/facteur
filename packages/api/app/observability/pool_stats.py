"""Introspection du pool SQLAlchemy, partagée par `/api/health/pool` (passif)
et la sonde pool périodique du scheduler (active).

Factorisé pour que l'endpoint de diagnostic et la sonde lisent le pool
exactement de la même manière.

Enabler observabilité scaling (WP-E) — cf.
docs/maintenance/maintenance-observabilite-scaling.md
"""

from __future__ import annotations

from typing import Any

import structlog
from sqlalchemy.ext.asyncio import AsyncEngine

logger = structlog.get_logger()


def read_pool_stats(engine: AsyncEngine) -> dict[str, Any]:
    """Lit les compteurs du pool dans un dict simple.

    `usage_pct` rapporte `checked_out` à la **capacité** du pool
    (`pool_size + max_overflow`, = 20 en prod). Piège SQLAlchemy à l'origine du
    faux positif PYTHON-63 : `pool.overflow()` n'est pas `max_overflow`, c'est
    le nombre de connexions *vivantes* au-delà de `pool_size` — s'en servir au
    dénominateur fait saturer la métrique à 100 % dès que la file d'idle se
    vide. Cf. docs/bugs/bug-pool-pressure-metric-false-positive.md.

    Défensif : NullPool (dev local) n'expose aucun compteur, donc chaque getter
    retombe sur `None` et `usage_pct` est omis.
    """
    pool = engine.pool
    size = getattr(pool, "size", lambda: None)()
    checked_in = getattr(pool, "checkedin", lambda: None)()
    checked_out = getattr(pool, "checkedout", lambda: None)()
    overflow = getattr(pool, "overflow", lambda: None)()
    # Pas d'accesseur public pour max_overflow ; `_max_overflow` est stable de
    # SQLAlchemy 1.4 à 2.0. NullPool ne l'expose pas → None (comme size()).
    max_overflow = getattr(pool, "_max_overflow", None)

    # Capacité inconnue si le pool n'est pas dimensionné (NullPool) ou si
    # max_overflow est illisible / négatif (= illimité côté SQLAlchemy).
    capacity = (
        size + max_overflow
        if size is not None and max_overflow is not None and max_overflow >= 0
        else None
    )

    if capacity is None and size is not None:
        # Pool dimensionné mais capacité illisible : sans `usage_pct` la sonde
        # de `scheduler.py` prend la branche « NullPool » et n'alerte plus du
        # tout. Ce silence est le pire mode de défaillance pour une métrique
        # d'alerte — on le rend bruyant plutôt que de le laisser passer.
        logger.error(
            "pool_capacity_unreadable",
            pool_class=type(pool).__name__,
            size=size,
            max_overflow=max_overflow,
        )

    measurable = checked_out is not None and capacity is not None and capacity > 0

    stats: dict[str, Any] = {
        "status": "saturated" if measurable and checked_out >= capacity else "ok",
        "pool_class": type(pool).__name__,
        "size": size,
        "checked_in": checked_in,
        "checked_out": checked_out,
        # Diagnostic seulement — jamais un dénominateur (cf. docstring).
        "overflow": overflow,
        "max_overflow": max_overflow,
        "capacity": capacity,
    }

    if measurable:
        stats["usage_pct"] = round(checked_out / capacity * 100, 1)

    return stats
