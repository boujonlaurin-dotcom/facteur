"""Introspection du pool SQLAlchemy, partagée par `/api/health/pool` (passif)
et la sonde pool périodique du scheduler (active).

Factorisé pour que l'endpoint de diagnostic et la sonde lisent le pool
exactement de la même manière.

Enabler observabilité scaling (WP-E) — cf.
docs/maintenance/maintenance-observabilite-scaling.md
"""

from __future__ import annotations

from typing import Any

from sqlalchemy.ext.asyncio import AsyncEngine


def read_pool_stats(engine: AsyncEngine) -> dict[str, Any]:
    """Lit les compteurs du pool dans un dict simple.

    Défensif : NullPool (dev local) n'expose pas `size()`/`checkedout()`, donc
    chaque getter retombe sur `None`. `usage_pct` n'est calculé que lorsque la
    taille est connue et > 0.
    """
    pool = engine.pool
    size = getattr(pool, "size", lambda: None)()
    checked_in = getattr(pool, "checkedin", lambda: None)()
    checked_out = getattr(pool, "checkedout", lambda: None)()
    overflow = getattr(pool, "overflow", lambda: None)()

    saturated = (
        checked_out is not None
        and size is not None
        and checked_out >= size + max(overflow or 0, 0)
    )

    stats: dict[str, Any] = {
        "status": "saturated" if saturated else "ok",
        "pool_class": type(pool).__name__,
        "size": size,
        "checked_in": checked_in,
        "checked_out": checked_out,
        "overflow": overflow,
    }

    if checked_out is not None and size is not None and size > 0:
        usage_pct = checked_out / (size + max(overflow or 0, 0))
        stats["usage_pct"] = round(usage_pct * 100, 1)

    return stats
