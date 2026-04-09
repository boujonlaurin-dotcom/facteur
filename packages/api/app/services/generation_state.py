"""In-memory state for digest batch generation.

Tracks whether the batch job is currently running so that API endpoints
can return HTTP 202 instead of blocking on on-demand generation.

This is per-process (no Redis needed) because APScheduler and the API
run in the same Railway container.
"""

import time

import structlog

logger = structlog.get_logger()

_SAFETY_TIMEOUT = 600  # 10 minutes — auto-reset if generation hangs
# Tightened from 30 min: the batch job should never legitimately run
# anywhere near that long, and a shorter window means a crashed-but-not-
# reset flag only blocks on-demand generation for 10 minutes instead of
# half an hour, reducing the surface area of the "stuck digest" bug.

_is_running: bool = False
_started_at: float | None = None


def mark_generation_started() -> None:
    """Called at the start of run_digest_generation()."""
    global _is_running, _started_at
    _is_running = True
    _started_at = time.monotonic()
    logger.info("generation_state_started")


def mark_generation_finished() -> None:
    """Called at the end of run_digest_generation() (success or failure)."""
    global _is_running, _started_at
    _is_running = False
    _started_at = None
    logger.info("generation_state_finished")


def is_generation_running() -> bool:
    """Check if the batch job is currently running.

    Returns False if the safety timeout has elapsed (stuck job protection).
    """
    if not _is_running:
        return False
    if _started_at is not None and (time.monotonic() - _started_at) > _SAFETY_TIMEOUT:
        logger.warning(
            "generation_state_safety_timeout",
            elapsed_s=round(time.monotonic() - _started_at),
        )
        return False
    return True
