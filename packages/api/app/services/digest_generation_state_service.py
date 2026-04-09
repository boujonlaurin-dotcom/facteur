"""Service layer for the `digest_generation_state` observability table.

Used by the digest batch and the on-read background regen to record where
each user is in the generation lifecycle, so operators can answer:

    "Why is user X still on yesterday's digest at 10am?"

...without scanning logs. All helpers UPSERT and are safe to call many times
per user per day.
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


async def mark_pending(
    session: AsyncSession,
    user_id: UUID,
    target_date: datetime.date,
) -> None:
    """Record that a user is queued for generation (no attempt yet)."""
    now = datetime.datetime.utcnow()
    stmt = (
        pg_insert(DigestGenerationState)
        .values(
            user_id=user_id,
            target_date=target_date,
            status="pending",
            attempts=0,
            created_at=now,
            updated_at=now,
        )
        .on_conflict_do_update(
            index_elements=["user_id", "target_date"],
            set_={"status": "pending", "updated_at": now},
        )
    )
    try:
        await session.execute(stmt)
    except Exception:
        logger.exception(
            "digest_generation_state_mark_pending_failed",
            user_id=str(user_id),
            target_date=str(target_date),
        )


async def mark_in_progress(
    session: AsyncSession,
    user_id: UUID,
    target_date: datetime.date,
) -> None:
    """Record that a worker has picked up this user."""
    now = datetime.datetime.utcnow()
    stmt = (
        pg_insert(DigestGenerationState)
        .values(
            user_id=user_id,
            target_date=target_date,
            status="in_progress",
            attempts=1,
            started_at=now,
            created_at=now,
            updated_at=now,
        )
        .on_conflict_do_update(
            index_elements=["user_id", "target_date"],
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
        logger.exception(
            "digest_generation_state_mark_in_progress_failed",
            user_id=str(user_id),
            target_date=str(target_date),
        )


async def mark_success(
    session: AsyncSession,
    user_id: UUID,
    target_date: datetime.date,
) -> None:
    """Record successful generation for this (user, date)."""
    now = datetime.datetime.utcnow()
    stmt = (
        pg_insert(DigestGenerationState)
        .values(
            user_id=user_id,
            target_date=target_date,
            status="success",
            attempts=1,
            finished_at=now,
            created_at=now,
            updated_at=now,
        )
        .on_conflict_do_update(
            index_elements=["user_id", "target_date"],
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
        logger.exception(
            "digest_generation_state_mark_success_failed",
            user_id=str(user_id),
            target_date=str(target_date),
        )


async def mark_failed(
    session: AsyncSession,
    user_id: UUID,
    target_date: datetime.date,
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
            status="failed",
            attempts=1,
            last_error=truncated,
            finished_at=now,
            created_at=now,
            updated_at=now,
        )
        .on_conflict_do_update(
            index_elements=["user_id", "target_date"],
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
        logger.exception(
            "digest_generation_state_mark_failed_failed",
            user_id=str(user_id),
            target_date=str(target_date),
        )


async def get_failed_users(
    session: AsyncSession,
    target_date: datetime.date,
) -> list[UUID]:
    """Return user ids whose last attempt for `target_date` failed.

    Used by observability / dashboard queries.
    """
    stmt = select(DigestGenerationState.user_id).where(
        DigestGenerationState.target_date == target_date,
        DigestGenerationState.status == "failed",
    )
    result = await session.execute(stmt)
    return list(result.scalars().all())
