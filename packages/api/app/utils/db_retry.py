"""Retry helper for transient DB errors.

Targets the recurring Sentry issues observed on read endpoints under pool
pressure :

- ``OperationalError: server closed the connection unexpectedly`` (PYTHON-4)
- ``InternalError: Unable to check out connection from the pool`` (PYTHON-26)
- ``InternalError: DbHandler exited`` (PYTHON-27 / PYTHON-1Q)
- ``PendingRollbackError: Can't reconnect until invalid transaction is
  rolled back`` (PYTHON-14)

The helper rolls back the active session before each retry so that a
session left in ``PendingRollbackError`` state can recover instead of
amplifying the failure.
"""

from __future__ import annotations

import asyncio
import logging
from collections.abc import Awaitable, Callable

from sqlalchemy.exc import (
    DBAPIError,
    InternalError,
    OperationalError,
    PendingRollbackError,
)
from sqlalchemy.ext.asyncio import AsyncSession

logger = logging.getLogger(__name__)

TRANSIENT_DB_ERRORS: tuple[type[Exception], ...] = (
    OperationalError,
    InternalError,
    PendingRollbackError,
    DBAPIError,
)


async def retry_db_op[T](
    op: Callable[[], Awaitable[T]],
    session: AsyncSession,
    *,
    max_attempts: int = 3,
    base_delay: float = 0.1,
    max_delay: float = 1.0,
    op_name: str = "db_op",
) -> T:
    """Run ``op()`` with retries on transient DB errors.

    On each retryable failure the active ``session`` is rolled back, then
    we sleep with exponential backoff (capped at ``max_delay``) and retry.
    The last exception is re-raised after ``max_attempts``.

    ``op`` is a zero-arg async factory so it can be re-invoked freshly on
    each attempt (the awaitable returned by a previous call is exhausted).
    """
    last_exc: Exception | None = None
    for attempt in range(1, max_attempts + 1):
        try:
            return await op()
        except TRANSIENT_DB_ERRORS as exc:
            last_exc = exc
            try:
                await session.rollback()
            except Exception as rb_exc:
                logger.debug(
                    "retry_db_rollback_failed op=%s error=%s",
                    op_name,
                    str(rb_exc)[:200],
                )
            if attempt >= max_attempts:
                break
            delay = min(base_delay * (2 ** (attempt - 1)), max_delay)
            logger.warning(
                "retry_db_op op=%s attempt=%d/%d exc=%s next_delay=%.2fs",
                op_name,
                attempt,
                max_attempts,
                type(exc).__name__,
                delay,
            )
            await asyncio.sleep(delay)
    assert last_exc is not None
    raise last_exc
