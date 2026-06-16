"""Budget mensuel persistant des appels API externes (Mistral / Brave).

Source de vérité : la table append-only `api_usage_events` (alimentée par
`usage_recorder`). Remplace les compteurs en mémoire `_brave_calls_month` /
`_mistral_calls_month` de `smart_source_search`, qui étaient remis à zéro à
**chaque restart de process** (donc à chaque déploiement Railway) → les caps
mensuels n'étaient en pratique jamais atteints. Compter les lignes du mois
calendaire courant survit aux restarts.

Le COUNT est mis en cache courte durée (TTL) pour ne pas requêter à chaque
appel de recherche ; un léger sous-comptage dans la fenêtre de TTL est sans
conséquence sur un cap mensuel de l'ordre du millier.

Note concurrence : le check de cap lit le compteur *avant* que l'appel ne
soit enregistré (l'INSERT a lieu après, via `track_api_call`), et chaque
process (API, worker) a son propre cache. Plusieurs appels concurrents
peuvent donc tous voir count < cap et partir — léger dépassement borné,
acceptable à l'échelle d'un budget mensuel.

Gouvernance coût scaling (PR-S3) — cf.
docs/maintenance/maintenance-scaling-cost-governance.md
"""

from __future__ import annotations

import time
from datetime import UTC, datetime

import structlog
from sqlalchemy import func, select

from app.config import get_settings
from app.database import safe_async_session
from app.models.api_usage_event import ApiUsageEvent

logger = structlog.get_logger()

# Cache process-local : { cache_key: (count, fetched_at_monotonic) }.
# La clé inclut le call_site quand il est précisé (compteurs distincts).
_cache: dict[str, tuple[int, float]] = {}


def _month_start_utc() -> datetime:
    now = datetime.now(UTC)
    return now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)


async def monthly_call_count(
    provider: str, *, call_site: str | None = None, force_refresh: bool = False
) -> int:
    """Nombre d'appels (status != error) ce mois calendaire (UTC).

    Si `call_site` est fourni, compte uniquement ce call site — sinon tout le
    provider. **Important** pour les caps : le provider `mistral` couvre
    classif + éditorial + veille + recherche ; ne plafonner que le call site
    voulu (ex. `smart_search_mistral`) évite que le trafic système ne consomme
    le budget du fallback recherche.

    Caché `cost_budget_cache_ttl_s` secondes. Best-effort : en cas d'erreur DB,
    renvoie la dernière valeur connue (ou 0), pour ne jamais bloquer un appel
    métier sur une panne d'observabilité.
    """
    cache_key = provider if call_site is None else f"{provider}:{call_site}"
    ttl = get_settings().cost_budget_cache_ttl_s
    now = time.monotonic()
    cached = _cache.get(cache_key)
    if not force_refresh and cached is not None and (now - cached[1]) < ttl:
        return cached[0]

    try:
        async with safe_async_session() as session:
            conditions = [
                ApiUsageEvent.provider == provider,
                ApiUsageEvent.created_at >= _month_start_utc(),
                ApiUsageEvent.status != "error",
            ]
            if call_site is not None:
                conditions.append(ApiUsageEvent.call_site == call_site)
            result = await session.execute(
                select(func.count()).select_from(ApiUsageEvent).where(*conditions)
            )
            count = int(result.scalar_one())
            _cache[cache_key] = (count, now)
            return count
    except Exception as exc:  # noqa: BLE001 — l'observabilité ne bloque jamais l'appelant
        logger.warning(
            "cost_budget.count_failed",
            provider=provider,
            call_site=call_site,
            error=str(exc),
            exc_type=type(exc).__name__,
        )
        return cached[0] if cached is not None else 0


async def is_over_cap(provider: str, cap: int, *, call_site: str | None = None) -> bool:
    """True si le call site (ou le provider) a atteint son cap mensuel."""
    if cap <= 0:
        return False
    return await monthly_call_count(provider, call_site=call_site) >= cap


def invalidate_cache() -> None:
    """Vide le cache (tests / réinitialisation explicite)."""
    _cache.clear()


async def monthly_usage_by_call_site() -> dict[str, dict[str, int]]:
    """Agrégat { provider: { call_site: count } } du mois courant (status ok).

    Sert au log de projection quotidien (évidence G3) : conso réelle par call
    site → projection à 200 users. Best-effort.
    """
    try:
        async with safe_async_session() as session:
            result = await session.execute(
                select(
                    ApiUsageEvent.provider,
                    ApiUsageEvent.call_site,
                    func.count().label("n"),
                )
                .where(
                    ApiUsageEvent.created_at >= _month_start_utc(),
                    ApiUsageEvent.status != "error",
                )
                .group_by(ApiUsageEvent.provider, ApiUsageEvent.call_site)
            )
            snapshot: dict[str, dict[str, int]] = {}
            for provider, call_site, n in result.all():
                snapshot.setdefault(provider, {})[call_site] = int(n)
            return snapshot
    except Exception as exc:  # noqa: BLE001
        logger.warning("cost_budget.snapshot_failed", error=str(exc))
        return {}


async def log_budget_projection(
    projection_factor: float = 2.25,
) -> dict[str, dict[str, int]]:
    """Émet `cost_budget_projection` : conso mois courant + projection ×facteur.

    `projection_factor` = ratio cible/actuel users (200 / ~89 ≈ 2.25 au
    baseline). Évidence G3 du scaling sans requête manuelle. Renvoie le
    snapshot pour les tests.
    """
    snapshot = await monthly_usage_by_call_site()
    projected = {
        provider: {cs: round(n * projection_factor) for cs, n in sites.items()}
        for provider, sites in snapshot.items()
    }
    logger.info(
        "cost_budget_projection",
        month_start=_month_start_utc().isoformat(),
        actual=snapshot,
        projected=projected,
        projection_factor=projection_factor,
    )
    return snapshot
