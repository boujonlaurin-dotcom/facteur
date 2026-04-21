"""Postgres-backed search cache with 24h TTL."""

import hashlib
import json
import re
from datetime import UTC, datetime, timedelta

import structlog
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

logger = structlog.get_logger()

CACHE_TTL_HOURS = 24


def normalize_query(query: str) -> str:
    """Normalize query for cache key: lowercase, strip, collapse whitespace."""
    return re.sub(r"\s+", " ", query.strip().lower())


def _build_cache_key(
    query: str, content_type: str | None, expand: bool
) -> str:
    normalized = normalize_query(query)
    return f"{normalized}|ct={content_type or '-'}|x={'1' if expand else '0'}"


def hash_query(
    query: str, content_type: str | None = None, expand: bool = False
) -> str:
    """SHA-256 hash of (normalized query, content_type, expand mode)."""
    return hashlib.sha256(
        _build_cache_key(query, content_type, expand).encode()
    ).hexdigest()


class SearchCache:
    """Postgres cache for smart search results (24h TTL)."""

    def __init__(self, db: AsyncSession) -> None:
        self.db = db

    async def get(
        self,
        query: str,
        content_type: str | None = None,
        expand: bool = False,
    ) -> dict | None:
        """Look up cached result. Returns None if miss or expired."""
        query_hash = hash_query(query, content_type, expand)
        now = datetime.now(UTC)

        result = await self.db.execute(
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

    async def set(
        self,
        query: str,
        payload: dict,
        content_type: str | None = None,
        expand: bool = False,
    ) -> None:
        """Insert or update cache entry with 24h TTL."""
        query_hash = hash_query(query, content_type, expand)
        raw = _build_cache_key(query, content_type, expand)
        now = datetime.now(UTC)
        expires = now + timedelta(hours=CACHE_TTL_HOURS)

        await self.db.execute(
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
        await self.db.flush()
        logger.info("search_cache.set", query_hash=query_hash[:12])
