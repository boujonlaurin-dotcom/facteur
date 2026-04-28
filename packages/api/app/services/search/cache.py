"""Postgres-backed search cache with 24h TTL."""

import hashlib
import json
import re
import unicodedata
from datetime import UTC, datetime, timedelta

import structlog
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import safe_async_session

logger = structlog.get_logger()

CACHE_TTL_HOURS = 24


def normalize_query(query: str) -> str:
    """Normalize query for cache key + matching.

    Strips accents (so "arret" matches "Arrêt"), lowercases, collapses
    whitespace. Mirrors the Postgres `unaccent(lower(...))` we apply on the
    catalog side so both ends compare equally-normalized strings.
    """
    stripped = unicodedata.normalize("NFKD", query)
    no_accents = "".join(c for c in stripped if not unicodedata.combining(c))
    return re.sub(r"\s+", " ", no_accents.strip().lower())


def _build_cache_key(query: str, content_type: str | None, expand: bool) -> str:
    normalized = normalize_query(query)
    return f"{normalized}|ct={content_type or '-'}|x={'1' if expand else '0'}"


def hash_query(
    query: str, content_type: str | None = None, expand: bool = False
) -> str:
    """SHA-256 hash of (normalized query, content_type, expand mode)."""
    return hashlib.sha256(
        _build_cache_key(query, content_type, expand).encode()
    ).hexdigest()


async def search_cache_get(
    session: AsyncSession,
    query: str,
    content_type: str | None = None,
    expand: bool = False,
) -> dict | None:
    """Look up cached result via the caller's session. Returns None if miss/expired."""
    query_hash = hash_query(query, content_type, expand)
    now = datetime.now(UTC)

    result = await session.execute(
        text(
            "SELECT payload FROM source_search_cache "
            "WHERE query_hash = :hash AND expires_at > :now"
        ),
        {"hash": query_hash, "now": now},
    )
    row = result.fetchone()
    if row:
        logger.info("search_cache.hit", query_hash=query_hash[:12])
        return row[0] if isinstance(row[0], dict) else json.loads(row[0])
    return None


async def search_cache_set(
    query: str,
    payload: dict,
    content_type: str | None = None,
    expand: bool = False,
) -> None:
    """Insert or update cache entry with 24h TTL using a short-lived session.

    The smart-search hot path releases its injected DB session before slow
    external HTTP calls; the cache write happens after, so we can't reuse it.
    """
    query_hash = hash_query(query, content_type, expand)
    raw = _build_cache_key(query, content_type, expand)
    now = datetime.now(UTC)
    expires = now + timedelta(hours=CACHE_TTL_HOURS)

    try:
        async with safe_async_session() as session:
            await session.execute(
                text(
                    "INSERT INTO source_search_cache "
                    "(query_hash, query_raw, payload, created_at, expires_at) "
                    "VALUES (:hash, :raw, :payload, :now, :expires) "
                    "ON CONFLICT (query_hash) DO UPDATE SET "
                    "payload = :payload, created_at = :now, expires_at = :expires"
                ),
                {
                    "hash": query_hash,
                    "raw": raw,
                    "payload": json.dumps(payload),
                    "now": now,
                    "expires": expires,
                },
            )
            await session.commit()
        logger.info("search_cache.set", query_hash=query_hash[:12])
    except Exception as exc:
        logger.warning(
            "search_cache.set_failed",
            error=str(exc),
            exc_type=type(exc).__name__,
        )
