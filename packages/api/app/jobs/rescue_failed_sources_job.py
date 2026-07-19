"""Weekly rescue of failed source adds (Story 12.2, T3-job).

Replays the collection + classification of failed/zero-result source signals
and logs the per-category counts. The distinct ``no_feed`` host count is the
**gating signal for Palier 2** (build scraping only if this tail grows past a
threshold). Read-only: never adds a source, never mutates a signal.

Runs at night (cohérent with storage_cleanup/purge) and is bounded so it can
never dominate the scheduler: at most ``_MAX_RESOLUTIONS`` live ``detect()``
re-resolutions, each under a short timeout.
"""

from __future__ import annotations

import asyncio
from datetime import UTC, datetime, timedelta

import structlog
from sqlalchemy import select

from app.database import safe_async_session
from app.services.rescue import (
    classify_all,
    collect_signals_from_db,
    infer_abandons,
    summarize,
)

logger = structlog.get_logger()

_WINDOW_DAYS = 90
# Cap on live re-resolutions so the night job stays light regardless of how
# many URL/reddit signals accumulated.
_MAX_RESOLUTIONS = 60
_RESOLVE_TIMEOUT_S = 12.0


def _make_resolver(max_resolutions: int):
    """Return an async ``resolver(url) -> bool`` with a global resolution cap.

    Once the cap is hit, further calls return False without touching the
    network — the signal is simply left classified as ``no_feed``, which is the
    conservative (never over-count "fixed") default and is logged.
    """
    from app.services.rss_parser import RSSParser

    state = {"used": 0}

    async def resolver(url: str) -> bool:
        if state["used"] >= max_resolutions:
            return False
        state["used"] += 1
        parser = RSSParser()
        try:
            detected = await asyncio.wait_for(
                parser.detect(url), timeout=_RESOLVE_TIMEOUT_S
            )
            return bool(detected and detected.feed_url)
        except Exception:
            return False
        finally:
            await parser.close()

    return resolver


async def _count_inferred_abandons(session, days: int) -> int:
    """T0.4b — searches with results but no add by the same user in-window."""
    from app.models.source import UserSource
    from app.models.source_search_log import SourceSearchLog

    cutoff = datetime.now(UTC) - timedelta(days=days)
    logs_rows = (
        await session.execute(
            select(
                SourceSearchLog.user_id,
                SourceSearchLog.created_at,
                SourceSearchLog.query_normalized,
            ).where(
                SourceSearchLog.created_at >= cutoff,
                SourceSearchLog.result_count > 0,
            )
        )
    ).all()
    adds_rows = (
        await session.execute(
            select(UserSource.user_id, UserSource.added_at).where(
                UserSource.added_at >= cutoff
            )
        )
    ).all()

    result_logs = [
        {
            "user_id": r.user_id,
            "created_at": r.created_at,
            "query_normalized": r.query_normalized,
        }
        for r in logs_rows
    ]
    user_source_added = [
        {"user_id": r.user_id, "added_at": r.added_at} for r in adds_rows
    ]
    return len(infer_abandons(result_logs, user_source_added))


async def run_rescue_failed_sources() -> dict:
    """Collect + classify the rescue signals and log the gating counters."""
    logger.info("rescue_failed_sources_started", window_days=_WINDOW_DAYS)
    try:
        async with safe_async_session() as session:
            try:
                signals = await collect_signals_from_db(session, days=_WINDOW_DAYS)
                resolver = _make_resolver(_MAX_RESOLUTIONS)
                classified = await classify_all(signals, resolver)
                summary = summarize(classified)
                summary["inferred_abandons"] = await _count_inferred_abandons(
                    session, _WINDOW_DAYS
                )
            finally:
                try:
                    await session.rollback()
                except Exception:
                    logger.warning("rescue outer rollback failed", exc_info=True)

        logger.info(
            "rescue_failed_sources_completed",
            window_days=_WINDOW_DAYS,
            total_signals=summary["total"],
            by_category=summary["by_category"],
            no_feed_host_count=summary["no_feed_host_count"],
            no_feed_hosts=summary["no_feed_hosts"],
            inferred_abandons=summary["inferred_abandons"],
        )
        return summary
    except Exception:
        logger.exception("rescue_failed_sources_failed")
        return {}
