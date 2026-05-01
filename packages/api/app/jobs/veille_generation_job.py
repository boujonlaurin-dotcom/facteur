"""Génération des livraisons de veille — scanner */30 min.

Pool DB : le scan est UN SELECT sur `ix_veille_configs_next_scheduled` puis
session fermée AVANT tout traitement. Chaque config a une session dédiée
bornée par un semaphore (incidents historiques de saturation pool, cf.
`docs/bugs/bug-infinite-load-requests.md`).
"""

from __future__ import annotations

import asyncio
from datetime import UTC, date, datetime
from uuid import UUID

import structlog
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import safe_async_session
from app.models.veille import (
    VeilleConfig,
    VeilleDelivery,
    VeilleGenerationState,
    VeilleStatus,
)
from app.services.veille.scheduling import compute_next_scheduled_at
from app.utils.time import today_paris

logger = structlog.get_logger()

_CONCURRENCY_LIMIT = 5
_SCAN_LIMIT = 500


async def run_veille_generation(target_date: date | None = None) -> None:
    """Scanner périodique : génère les livraisons des configs `due`."""
    target = target_date or today_paris()
    started_at = datetime.now(UTC)

    logger.info("veille_generation_job_started", target_date=str(target))

    async with safe_async_session() as scan_session:
        configs_due = (
            (
                await scan_session.execute(
                    select(VeilleConfig)
                    .where(
                        VeilleConfig.status == VeilleStatus.ACTIVE.value,
                        VeilleConfig.next_scheduled_at <= started_at,
                    )
                    .limit(_SCAN_LIMIT)
                )
            )
            .scalars()
            .all()
        )
        config_ids = [c.id for c in configs_due]

    if not config_ids:
        logger.info("veille_generation_job_no_due", target_date=str(target))
        return

    semaphore = asyncio.Semaphore(_CONCURRENCY_LIMIT)
    results = await asyncio.gather(
        *(_process_config_with_semaphore(semaphore, cid, target) for cid in config_ids),
        return_exceptions=True,
    )

    succeeded = sum(1 for r in results if r is True)
    failed = sum(1 for r in results if isinstance(r, Exception) or r is False)

    logger.info(
        "veille_generation_job_completed",
        target_date=str(target),
        configs_processed=len(config_ids),
        succeeded=succeeded,
        failed=failed,
    )


async def _process_config_with_semaphore(
    semaphore: asyncio.Semaphore,
    config_id: UUID,
    target: date,
) -> bool:
    async with semaphore, safe_async_session() as session:
        try:
            await run_veille_generation_for_config(
                session, config_id, target_date=target
            )
            await session.commit()
            return True
        except Exception as exc:
            await session.rollback()
            logger.error(
                "veille_generation_job_config_failed",
                config_id=str(config_id),
                error=str(exc),
            )
            return False


async def run_veille_generation_for_config(
    session: AsyncSession,
    config_id: UUID,
    target_date: date,
) -> VeilleDelivery:
    """Génère (ou met à jour) la livraison pour une config + date données.

    Idempotent via UPSERT sur (`veille_config_id`, `target_date`). Le caller
    assure le `commit()` (utilisé depuis le job ET depuis la route debug).
    """
    cfg = (
        (
            await session.execute(
                select(VeilleConfig).where(VeilleConfig.id == config_id)
            )
        )
        .scalars()
        .first()
    )
    if cfg is None:
        raise ValueError(f"VeilleConfig introuvable: {config_id}")

    started_at = datetime.now(UTC)

    upsert_stmt = (
        pg_insert(VeilleDelivery)
        .values(
            veille_config_id=config_id,
            target_date=target_date,
            generation_state=VeilleGenerationState.RUNNING.value,
            attempts=1,
            started_at=started_at,
        )
        .on_conflict_do_update(
            index_elements=["veille_config_id", "target_date"],
            set_={
                "generation_state": VeilleGenerationState.RUNNING.value,
                "started_at": started_at,
                "attempts": VeilleDelivery.attempts + 1,
            },
        )
        .returning(VeilleDelivery.id)
    )
    delivery_id = (await session.execute(upsert_stmt)).scalar_one()
    delivery = await session.get(VeilleDelivery, delivery_id)
    assert delivery is not None

    finished_at = datetime.now(UTC)
    delivery.generation_state = VeilleGenerationState.SUCCEEDED.value
    delivery.items = []
    delivery.finished_at = finished_at
    delivery.generated_at = finished_at
    delivery.last_error = None

    # Recalcule next_scheduled_at + last_delivered_at.
    cfg.last_delivered_at = finished_at
    cfg.next_scheduled_at = compute_next_scheduled_at(
        frequency=cfg.frequency,
        day_of_week=cfg.day_of_week,
        delivery_hour=cfg.delivery_hour,
        timezone=cfg.timezone,
        last_delivered_at=cfg.last_delivered_at,
        now=finished_at,
    )

    await session.flush()

    logger.info(
        "veille_generation_config_processed",
        config_id=str(config_id),
        target_date=str(target_date),
        next_scheduled_at=cfg.next_scheduled_at.isoformat()
        if cfg.next_scheduled_at
        else None,
    )

    return delivery
