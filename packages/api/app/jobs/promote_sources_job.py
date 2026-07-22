"""Job hebdo : promotion catalogue (`is_curated`) du backlog évalué.

Cause racine du sous-fonctionnement (cf. plan sources-theme-coverage) : la
promotion des sources évaluées vers le catalogue curé ne tournait qu'au
lancement **manuel** de `scripts/retag_and_promote_sources.py`, donc un backlog
de sources qualité restait invisible à la reco « Étoffer [thème] ». On planifie
ici la même promotion, en réutilisant la **logique pure + la couche DB** du
script (une seule source de vérité pour le gate).

Ce job **ne promeut que** (`is_curated=false -> true`) — il ne touche jamais
`granular_topics` (re-tag réservé au run manuel avec revue du CSV master par le
PO). Gate strict, aligné sur le gate de recommandation : biais connu **et non
`alternative`**, fiabilité medium/high, volume >= seuil, et URL hors denylist
éditoriale (`PROMO_DENYLIST`). Idempotent : `NOT is_curated` filtre les sources
déjà promues, donc un 2e passage (ou le double run staging+prod sur la DB
partagée) est un no-op.

⚠️ Additif uniquement (expand-contract, DB partagée staging/prod) : flipper
`is_curated` à true est sûr pour le backend prod (ancien code) qui lit la même
colonne via son propre gate de reco.
"""

from __future__ import annotations

import structlog

from app.database import safe_async_session
from scripts.retag_and_promote_sources import (
    compute_promotions,
    load_metas,
    write_promotions,
)

logger = structlog.get_logger()


async def promote_evaluated_sources() -> None:
    """Promeut le backlog de sources évaluées franchissant le gate de promotion.

    Read → `compute_promotions` (gate strict + denylist, sans re-tag ni audit) →
    apply promotions only. Logue les noms promus (audit Railway/Sentry) ; aucune
    exception ne remonte au scheduler (best-effort, comme les autres jobs
    hebdo). `safe_async_session` garantit le rollback en sortie."""
    try:
        async with safe_async_session() as session:
            metas = await load_metas(session)
            promotions = compute_promotions(metas)

            if not promotions:
                logger.info(
                    "source_promotion_no_candidates", active_sources=len(metas)
                )
                return

            await write_promotions(session, promotions)
            await session.commit()
            logger.info(
                "source_promotion_applied",
                count=len(promotions),
                names=[p.name for p in promotions],
            )
    except Exception as exc:
        logger.error(
            "source_promotion_failed",
            error=str(exc),
            error_type=type(exc).__name__,
            exc_info=True,
        )
