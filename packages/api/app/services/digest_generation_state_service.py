"""Service layer for the `digest_generation_state` observability table.

Used by the digest batch and the on-read background regen to record where
each user variant is in the generation lifecycle, so operators can answer:

    "Why is user X still on yesterday's digest at 10am?"

...without scanning logs. All helpers UPSERT on
`(user_id, target_date, is_serene)` and are safe to call many times per
variant per day. `is_serene` is required so the pour_vous and serein
variants are tracked independently — a half-broken user must not look
identical to a fully-working one.
"""

from __future__ import annotations

import datetime
from uuid import UUID

import structlog
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.digest_generation_state import DigestGenerationState

logger = structlog.get_logger()

_CONFLICT_COLS = ["user_id", "target_date", "is_serene"]


async def mark_pending(
    session: AsyncSession,
    user_id: UUID,
    target_date: datetime.date,
    is_serene: bool,
) -> None:
    """Record that a (user, variant) is queued for generation (no attempt yet)."""
    now = datetime.datetime.utcnow()
    stmt = (
        pg_insert(DigestGenerationState)
        .values(
            user_id=user_id,
            target_date=target_date,
            is_serene=is_serene,
            status="pending",
            attempts=0,
            created_at=now,
            updated_at=now,
        )
        .on_conflict_do_update(
            index_elements=_CONFLICT_COLS,
            set_={"status": "pending", "updated_at": now},
        )
    )
    try:
        await session.execute(stmt)
    except Exception:
        await session.rollback()
        logger.exception(
            "digest_generation_state_mark_pending_failed",
            user_id=str(user_id),
            target_date=str(target_date),
            is_serene=is_serene,
        )


async def mark_in_progress(
    session: AsyncSession,
    user_id: UUID,
    target_date: datetime.date,
    is_serene: bool,
) -> None:
    """Record that a worker has picked up this (user, variant)."""
    now = datetime.datetime.utcnow()
    stmt = (
        pg_insert(DigestGenerationState)
        .values(
            user_id=user_id,
            target_date=target_date,
            is_serene=is_serene,
            status="in_progress",
            attempts=1,
            started_at=now,
            created_at=now,
            updated_at=now,
        )
        .on_conflict_do_update(
            index_elements=_CONFLICT_COLS,
            set_={
                "status": "in_progress",
                "attempts": DigestGenerationState.attempts + 1,
                "started_at": now,
                "updated_at": now,
            },
        )
    )
    try:
        await session.execute(stmt)
    except Exception:
        await session.rollback()
        logger.exception(
            "digest_generation_state_mark_in_progress_failed",
            user_id=str(user_id),
            target_date=str(target_date),
            is_serene=is_serene,
        )


async def mark_success(
    session: AsyncSession,
    user_id: UUID,
    target_date: datetime.date,
    is_serene: bool,
) -> None:
    """Record successful generation for this (user, variant)."""
    now = datetime.datetime.utcnow()
    stmt = (
        pg_insert(DigestGenerationState)
        .values(
            user_id=user_id,
            target_date=target_date,
            is_serene=is_serene,
            status="success",
            attempts=1,
            finished_at=now,
            created_at=now,
            updated_at=now,
        )
        .on_conflict_do_update(
            index_elements=_CONFLICT_COLS,
            set_={
                "status": "success",
                "last_error": None,
                "finished_at": now,
                "updated_at": now,
            },
        )
    )
    try:
        await session.execute(stmt)
    except Exception:
        await session.rollback()
        logger.exception(
            "digest_generation_state_mark_success_failed",
            user_id=str(user_id),
            target_date=str(target_date),
            is_serene=is_serene,
        )


async def mark_failed(
    session: AsyncSession,
    user_id: UUID,
    target_date: datetime.date,
    is_serene: bool,
    error: str,
) -> None:
    """Record a failed generation attempt with the error message."""
    now = datetime.datetime.utcnow()
    # Truncate error message to a reasonable length for storage.
    truncated = (error or "")[:2000]
    stmt = (
        pg_insert(DigestGenerationState)
        .values(
            user_id=user_id,
            target_date=target_date,
            is_serene=is_serene,
            status="failed",
            attempts=1,
            last_error=truncated,
            finished_at=now,
            created_at=now,
            updated_at=now,
        )
        .on_conflict_do_update(
            index_elements=_CONFLICT_COLS,
            set_={
                "status": "failed",
                "last_error": truncated,
                "attempts": DigestGenerationState.attempts + 1,
                "finished_at": now,
                "updated_at": now,
            },
        )
    )
    try:
        await session.execute(stmt)
    except Exception:
        await session.rollback()
        logger.exception(
            "digest_generation_state_mark_failed_failed",
            user_id=str(user_id),
            target_date=str(target_date),
            is_serene=is_serene,
        )


async def get_failed_variants(
    session: AsyncSession,
    target_date: datetime.date,
) -> list[tuple[UUID, bool]]:
    """Return (user_id, is_serene) pairs whose last attempt for `target_date` failed.

    Returns pairs rather than distinct users so the caller can see exactly
    which variant is broken (one user can have pour_vous success + serein
    failed).
    """
    stmt = select(
        DigestGenerationState.user_id,
        DigestGenerationState.is_serene,
    ).where(
        DigestGenerationState.target_date == target_date,
        DigestGenerationState.status == "failed",
    )
    result = await session.execute(stmt)
    return [(row.user_id, row.is_serene) for row in result]
