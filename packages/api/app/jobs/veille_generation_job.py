"""Génération des livraisons de veille — scanner */30 min.

Invariant : aucune session DB tenue pendant l'appel LLM (3-5 s). Cf.
incidents pool QueuePool docs/bugs/bug-infinite-load-requests.md (#363).
"""

from __future__ import annotations

import asyncio
from datetime import UTC, date, datetime
from uuid import UUID

import sentry_sdk
import structlog
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import SessionMaker, safe_async_session
from app.models.veille import (
    VeilleConfig,
    VeilleDelivery,
    VeilleGenerationState,
    VeilleStatus,
)
from app.services.editorial.llm_client import EditorialLLMClient
from app.services.veille.digest_builder import VeilleDigestBuilder
from app.services.veille.scheduling import compute_next_scheduled_at
from app.utils.time import today_paris

logger = structlog.get_logger()

_CONCURRENCY_LIMIT = 5
_SCAN_LIMIT = 500
# Hard cap pour éviter qu'une livraison reste en RUNNING indéfiniment quand
# le builder hang (LLM, DB, etc). 5 min couvre largement la p99 observée
# (~30 s) ; au-delà on FAILED + Sentry, le user reverra le retry au prochain run.
_BUILDER_TIMEOUT_SECONDS = 300
# Au-delà de ce délai, une row RUNNING est considérée morte (worker SIGKILL,
# OOM, restart Railway). Le watchdog log dans `_phase1_mark_running` permet de
# tracer la reprise — la row sera reset à RUNNING avec attempts++ via le
# on_conflict_do_update existant.
_STUCK_RUNNING_THRESHOLD_SECONDS = 600
# Filet final (job */5min) : si une row reste RUNNING > 15 min sans transition
# FAILED, c'est qu'aucun re-scan ne la touchera (le scanner ne reprend que les
# configs `due`, et le watchdog `_phase1_mark_running` ne fire que si elle est
# rescannée). On la marque FAILED + Sentry pour qu'elle disparaisse de l'UI.
_STUCK_CLEANUP_THRESHOLD_SECONDS = 900


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

    llm = EditorialLLMClient()
    builder = VeilleDigestBuilder(llm=llm, session_maker=safe_async_session)

    try:
        semaphore = asyncio.Semaphore(_CONCURRENCY_LIMIT)
        results = await asyncio.gather(
            *(
                _process_config_with_semaphore(semaphore, cid, target, builder)
                for cid in config_ids
            ),
            return_exceptions=True,
        )
    finally:
        await llm.close()

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
    builder: VeilleDigestBuilder,
) -> bool:
    async with semaphore:
        try:
            await run_veille_generation_for_config(
                config_id,
                target_date=target,
                session_maker=safe_async_session,
                builder=builder,
            )
            return True
        except Exception as exc:  # noqa: BLE001 — catch-all pour persister FAILED
            await _mark_scanner_delivery_failed(config_id, target, exc)
            return False


async def _mark_scanner_delivery_failed(
    config_id: UUID,
    target: date,
    exc: BaseException,
) -> None:
    """UPSERT veille_deliveries → FAILED + sentry capture (best-effort).

    Invariant : la row a déjà été créée RUNNING par `_phase1_mark_running`
    si on est arrivés au LLM. Si l'exception est levée avant phase 1
    (cas rare), on UPSERT avec un id généré pour matérialiser l'échec
    côté table.
    """
    error_class = type(exc).__name__
    error_msg = f"{error_class}: {str(exc)[:480]}"
    try:
        async with safe_async_session() as s:
            delivery = (
                await s.execute(
                    select(VeilleDelivery).where(
                        VeilleDelivery.veille_config_id == config_id,
                        VeilleDelivery.target_date == target,
                    )
                )
            ).scalar_one_or_none()
            if delivery is None:
                logger.error(
                    "veille_generation_job_failed_row_missing",
                    config_id=str(config_id),
                    target_date=str(target),
                    error_class=error_class,
                )
            else:
                delivery.generation_state = VeilleGenerationState.FAILED.value
                delivery.last_error = error_msg
                delivery.finished_at = datetime.now(UTC)
                delivery.attempts = (delivery.attempts or 0) + 1
                await s.commit()
    except Exception as commit_exc:  # noqa: BLE001 — best-effort
        logger.error(
            "veille_generation_job_failed_persist_error",
            config_id=str(config_id),
            target_date=str(target),
            error=str(commit_exc),
        )

    sentry_sdk.capture_exception(exc)
    logger.error(
        "veille.scanner_delivery_failed_terminal",
        config_id=str(config_id),
        target_date=str(target),
        error_class=error_class,
        error_msg=str(exc)[:480],
    )


async def cleanup_stuck_running_deliveries() -> int:
    """Filet final : marque FAILED toute row RUNNING > 15 min.

    Couvre le cas worker SIGKILL/OOM Railway où ni le retry router (PR #561)
    ni le watchdog `_phase1_mark_running` (PR #577) ne reprennent la row
    parce qu'elle n'est plus jamais rescannée (config plus `due`). Tourne
    toutes les 5 min via le scheduler.
    """
    threshold = datetime.now(UTC).timestamp() - _STUCK_CLEANUP_THRESHOLD_SECONDS
    cutoff = datetime.fromtimestamp(threshold, tz=UTC)
    fixed = 0
    try:
        async with safe_async_session() as s:
            stuck_rows = (
                (
                    await s.execute(
                        select(VeilleDelivery).where(
                            VeilleDelivery.generation_state
                            == VeilleGenerationState.RUNNING.value,
                            VeilleDelivery.started_at.is_not(None),
                            VeilleDelivery.started_at < cutoff,
                        )
                    )
                )
                .scalars()
                .all()
            )
            for row in stuck_rows:
                stuck_seconds = (
                    int((datetime.now(UTC) - row.started_at).total_seconds())
                    if row.started_at is not None
                    else -1
                )
                row.generation_state = VeilleGenerationState.FAILED.value
                row.last_error = (
                    f"watchdog_cleanup: stuck >15min "
                    f"({stuck_seconds}s, no FAILED transition)"
                )
                row.finished_at = datetime.now(UTC)
                fixed += 1
                logger.warning(
                    "veille.watchdog_cleanup_marked_failed",
                    delivery_id=str(row.id),
                    config_id=str(row.veille_config_id),
                    target_date=str(row.target_date),
                    stuck_seconds=stuck_seconds,
                    attempts=row.attempts,
                )
                sentry_sdk.capture_message(
                    f"veille.watchdog_cleanup: delivery {row.id} stuck "
                    f"{stuck_seconds}s in RUNNING — marked FAILED",
                    level="warning",
                )
            if fixed:
                await s.commit()
    except Exception:  # noqa: BLE001 — best-effort, ne pas planter le scheduler
        logger.exception("veille.watchdog_cleanup_failed")
        return 0

    logger.info("veille.watchdog_cleanup_completed", fixed=fixed)
    return fixed


async def run_veille_generation_for_config(
    config_id: UUID,
    target_date: date,
    *,
    session_maker: SessionMaker,
    builder: VeilleDigestBuilder | None = None,
) -> VeilleDelivery:
    """Génère (ou met à jour) la livraison pour une config + date données.

    Pipeline 3-phase, sessions courtes — la session est commit + close
    AVANT l'appel LLM pour que la connexion soit rendue au pool. `builder
    is None` → `items=[]` (utilisé en tests).
    """
    async with session_maker() as s:
        delivery_id, _ = await _phase1_mark_running(s, config_id, target_date)
        await s.commit()

    items: list[dict] = []
    if builder is not None:
        items = await asyncio.wait_for(
            builder.build(config_id), timeout=_BUILDER_TIMEOUT_SECONDS
        )

    finished_at = datetime.now(UTC)
    async with session_maker() as s:
        delivery = await _phase3_persist(s, delivery_id, config_id, items, finished_at)
        await s.commit()
        await s.refresh(delivery)

    logger.info(
        "veille_generation_config_processed",
        config_id=str(config_id),
        target_date=str(target_date),
        item_count=len(items),
    )
    return delivery


async def _phase1_mark_running(
    session: AsyncSession,
    config_id: UUID,
    target_date: date,
) -> tuple[UUID, datetime]:
    """UPSERT veille_deliveries en état RUNNING. Retourne (delivery_id, started_at)."""
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

    # Watchdog : si une row RUNNING > _STUCK_RUNNING_THRESHOLD_SECONDS existe
    # déjà pour ce (config, date), c'est qu'un worker précédent a crashé sans
    # passer par _mark_scanner_delivery_failed. Le upsert qui suit la reset à
    # RUNNING+attempts++, on log explicitement pour que Sentry voie l'incident.
    existing = (
        await session.execute(
            select(VeilleDelivery).where(
                VeilleDelivery.veille_config_id == config_id,
                VeilleDelivery.target_date == target_date,
            )
        )
    ).scalar_one_or_none()
    if (
        existing is not None
        and existing.generation_state == VeilleGenerationState.RUNNING.value
        and existing.started_at is not None
        and (started_at - existing.started_at).total_seconds()
        > _STUCK_RUNNING_THRESHOLD_SECONDS
    ):
        logger.warning(
            "veille.stuck_running_reset",
            config_id=str(config_id),
            target_date=str(target_date),
            previous_started_at=existing.started_at.isoformat(),
            stuck_seconds=int((started_at - existing.started_at).total_seconds()),
            attempts=existing.attempts,
        )

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
    return delivery_id, started_at


async def _phase3_persist(
    session: AsyncSession,
    delivery_id: UUID,
    config_id: UUID,
    items: list[dict],
    finished_at: datetime,
) -> VeilleDelivery:
    """UPDATE delivery SUCCEEDED + recalc next_scheduled_at."""
    delivery = await session.get(VeilleDelivery, delivery_id)
    if delivery is None:
        raise ValueError(f"VeilleDelivery introuvable: {delivery_id}")

    delivery.generation_state = VeilleGenerationState.SUCCEEDED.value
    delivery.items = items
    delivery.finished_at = finished_at
    delivery.generated_at = finished_at
    delivery.last_error = None

    cfg = await session.get(VeilleConfig, config_id)
    if cfg is None:
        raise ValueError(f"VeilleConfig introuvable: {config_id}")
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
    return delivery
