"""Rescue of failed source adds — collection + classification (Story 12.2, T2/T3).

Shared, side-effect-light core reused by both:
  * the weekly scheduler job (``app/jobs/rescue_failed_sources_job.py``), which
    runs in-process against the DB, and
  * the standalone read-only script (``scripts/rescue_failed_sources.py``),
    which pulls the same signals via Supabase REST.

The classification is a **pure** function so it can be unit-tested with prod
fixtures without any network. Network re-resolution (``detect()``) is injected
as a ``resolver`` callback, so tests stub it.

Categories (the gating signal for Palier 2 is ``no_feed`` distinct hosts):
  * ``resolvable_rss``     — a URL that now resolves to a feed (incl. new WP rungs)
  * ``fixed_since``        — previously-failing class fixed in code (YouTube #939,
                             Reddit gap) — the feed exists, resolution is back
  * ``found_but_abandoned``— search returned results but the user didn't add →
                             UX/relevance, NOT an ingestion gap
  * ``no_feed``            — still no discoverable feed (the real Palier 2 tail)
  * ``invalid``            — typo / too-short / non-source keyword
"""

from __future__ import annotations

import re
from collections import Counter
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from urllib.parse import urlparse

from app.services.rss_parser import normalize_input_url
from app.services.search.cache import normalize_query

RESOLVABLE_RSS = "resolvable_rss"
FIXED_SINCE = "fixed_since"
FOUND_BUT_ABANDONED = "found_but_abandoned"
NO_FEED = "no_feed"
INVALID = "invalid"

CATEGORIES = (
    RESOLVABLE_RSS,
    FIXED_SINCE,
    FOUND_BUT_ABANDONED,
    NO_FEED,
    INVALID,
)

# A search that returned results but was not followed by an add within this
# window is treated as an inferred abandon (server-side complement to the
# client-dependent /search-abandoned signal — T0.4b).
ABANDON_INFERENCE_WINDOW = timedelta(hours=6)

_URL_RE = re.compile(r"^[\w.-]+\.[a-z]{2,}(/.*)?$", re.IGNORECASE)


@dataclass
class Signal:
    """A deduplicated failed/zero-result signal to reclassify."""

    key: str
    input_text: str
    kind: str  # "url" | "keyword"
    content_type: str | None = None
    max_result_count: int = 0
    abandoned: bool = False
    occurrences: int = 1
    user_ids: set[str] = field(default_factory=set)


def is_url_like(text: str) -> bool:
    """True when *text* looks like a URL/bare domain rather than a keyword."""
    t = (text or "").strip()
    if t.startswith(("http://", "https://")):
        return True
    return bool(_URL_RE.match(t))


def is_invalid_input(text: str) -> bool:
    """Heuristic for junk keywords (typos, too short, single word < 3 chars)."""
    normalized = normalize_query(text or "")
    return len(normalized.replace(" ", "")) < 3


def signal_key(text: str) -> str:
    """Stable dedup key: host+path for URLs, normalized query for keywords."""
    if is_url_like(text):
        candidate = text.strip()
        if not candidate.startswith(("http://", "https://")):
            candidate = "https://" + candidate
        parsed = urlparse(normalize_input_url(candidate))
        path = parsed.path.rstrip("/").lower()
        return f"{parsed.netloc}{path}" if parsed.netloc else normalize_query(text)
    return normalize_query(text)


def resolve_target(sig: Signal) -> str | None:
    """URL to re-resolve for this signal, or None when resolution is N/A.

    URLs re-resolve directly; reddit-ish keywords re-resolve via the
    ``/r/<sub>/.rss`` URL (drives the T0.3 gap fix). Other keywords aren't
    resolvable offline (they need the full ranked search), so they're
    classified from the log metadata alone.
    """
    text = sig.input_text.strip()
    if sig.kind == "url":
        candidate = text
        if not candidate.startswith(("http://", "https://")):
            candidate = "https://" + candidate
        return candidate
    ct = (sig.content_type or "").lower()
    if ct == "reddit" or text.lower().startswith("r/"):
        sub = text[2:] if text.lower().startswith("r/") else text
        sub = re.sub(r"[^A-Za-z0-9_]", "", sub)
        if sub:
            return f"https://www.reddit.com/r/{sub}/.rss"
    return None


def classify_signal(sig: Signal, resolvable: bool | None) -> str:
    """Pure classifier. ``resolvable`` = outcome of a (mocked) detect(), or None."""
    if sig.kind == "keyword" and is_invalid_input(sig.input_text):
        return INVALID

    if sig.kind == "url":
        return RESOLVABLE_RSS if resolvable else NO_FEED

    ct = (sig.content_type or "").lower()
    text = sig.input_text.strip().lower()

    # YouTube-filtered zero-result searches were the #939 layer bug — the
    # channel feeds exist; resolution is fixed in code.
    if ct == "youtube":
        return FIXED_SINCE

    if ct == "reddit" or text.startswith("r/"):
        if resolvable is True:
            return RESOLVABLE_RSS
        if resolvable is False:
            return NO_FEED
        # Resolution not attempted → the gap fix now routes it; treat as fixed.
        return FIXED_SINCE

    # Keyword that DID return results but wasn't added → UX/relevance, not a
    # missing feed.
    if sig.max_result_count and sig.max_result_count > 0:
        return FOUND_BUT_ABANDONED

    return NO_FEED


def merge_signal(
    signals: dict[str, Signal],
    *,
    input_text: str,
    kind: str,
    content_type: str | None = None,
    result_count: int = 0,
    abandoned: bool = False,
    user_id: str | None = None,
) -> None:
    """Fold one raw row into the deduplicated signal map (in place)."""
    key = signal_key(input_text)
    existing = signals.get(key)
    if existing is None:
        existing = Signal(
            key=key,
            input_text=input_text.strip(),
            kind=kind,
            content_type=content_type,
        )
        signals[key] = existing
    else:
        existing.occurrences += 1
    existing.max_result_count = max(existing.max_result_count, result_count or 0)
    existing.abandoned = existing.abandoned or abandoned
    if existing.content_type is None and content_type:
        existing.content_type = content_type
    if user_id:
        existing.user_ids.add(str(user_id))


async def classify_all(signals: list[Signal], resolver) -> list[dict]:
    """Classify each signal, calling ``resolver(url) -> bool`` where applicable.

    ``resolver`` may be None (metadata-only classification). Returns a list of
    dicts ready for JSON/markdown serialization.
    """
    out: list[dict] = []
    for sig in signals:
        target = resolve_target(sig)
        resolvable: bool | None = None
        if target is not None and resolver is not None:
            try:
                resolvable = bool(await resolver(target))
            except Exception:
                resolvable = False
        out.append(
            {
                "key": sig.key,
                "input_text": sig.input_text,
                "kind": sig.kind,
                "content_type": sig.content_type,
                "occurrences": sig.occurrences,
                "max_result_count": sig.max_result_count,
                "abandoned": sig.abandoned,
                "resolve_target": target,
                "resolvable": resolvable,
                "category": classify_signal(sig, resolvable),
            }
        )
    return out


def summarize(classified: list[dict]) -> dict:
    """Aggregate category counts + the distinct ``no_feed`` host set (the gate)."""
    counts = Counter(row["category"] for row in classified)
    no_feed_hosts: set[str] = set()
    for row in classified:
        if row["category"] != NO_FEED or row["kind"] != "url":
            continue
        target = row.get("resolve_target") or row["input_text"]
        host = urlparse(
            target if target.startswith("http") else f"https://{target}"
        ).netloc.lower()
        if host:
            no_feed_hosts.add(host)
    return {
        "total": len(classified),
        "by_category": {cat: counts.get(cat, 0) for cat in CATEGORIES},
        "no_feed_hosts": sorted(no_feed_hosts),
        "no_feed_host_count": len(no_feed_hosts),
    }


def infer_abandons(
    result_logs: list[dict],
    user_source_added: list[dict],
    *,
    window: timedelta = ABANDON_INFERENCE_WINDOW,
) -> list[dict]:
    """Server-side abandon inference (T0.4b).

    A search that returned results (``result_count > 0``) but is not followed
    by *any* source add by the same user within ``window`` is an inferred
    abandon — a signal the client-only ``/search-abandoned`` call under-counts.

    ``result_logs``: dicts with ``user_id``, ``created_at``, ``query_normalized``.
    ``user_source_added``: dicts with ``user_id``, ``added_at``.
    """
    adds_by_user: dict[str, list[datetime]] = {}
    for row in user_source_added:
        uid = str(row.get("user_id"))
        added = row.get("added_at")
        if uid and added is not None:
            adds_by_user.setdefault(uid, []).append(added)

    inferred: list[dict] = []
    for log in result_logs:
        uid = str(log.get("user_id"))
        created = log.get("created_at")
        if created is None:
            continue
        adds = adds_by_user.get(uid, [])
        if any(created <= a <= created + window for a in adds):
            continue
        inferred.append(
            {
                "user_id": uid,
                "query_normalized": log.get("query_normalized"),
                "created_at": created,
            }
        )
    return inferred


async def collect_signals_from_db(session, days: int = 90) -> list[Signal]:
    """Collect + dedupe rescue signals from the DB (weekly-job path)."""
    from sqlalchemy import or_, select

    from app.models.failed_source_attempt import FailedSourceAttempt
    from app.models.source_search_log import SourceSearchLog

    cutoff = datetime.now(UTC) - timedelta(days=days)
    signals: dict[str, Signal] = {}

    attempts = await session.execute(
        select(FailedSourceAttempt).where(FailedSourceAttempt.created_at >= cutoff)
    )
    for row in attempts.scalars().all():
        text = row.input_text or ""
        if not text.strip():
            continue
        merge_signal(
            signals,
            input_text=text,
            kind="url" if is_url_like(text) else "keyword",
            user_id=str(row.user_id),
        )

    logs = await session.execute(
        select(SourceSearchLog).where(
            SourceSearchLog.created_at >= cutoff,
            or_(SourceSearchLog.result_count == 0, SourceSearchLog.abandoned.is_(True)),
        )
    )
    for row in logs.scalars().all():
        text = row.query_raw or ""
        if not text.strip():
            continue
        merge_signal(
            signals,
            input_text=text,
            kind="url" if is_url_like(text) else "keyword",
            content_type=row.content_type,
            result_count=row.result_count,
            abandoned=row.abandoned,
            user_id=str(row.user_id),
        )

    return list(signals.values())
