"""Postgres-backed search cache with 24h TTL."""

import hashlib
import json
import re
from datetime import datetime, timedelta, timezone

import structlog
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

logger = structlog.get_logger()

CACHE_TTL_HOURS = 24


def normalize_query(query: str) -> str:
    """Normalize query for cache key: lowercase, strip, collapse whitespace."""
    return re.sub(r"\s+", " ", query.strip().lower())


def hash_query(query: str) -> str:
    """SHA-256 hash of normalized query."""
    normalized = normalize_query(query)
    return hashlib.sha256(normalized.encode()).hexdigest()


class SearchCache:
    """Postgres cache for smart search results (24h TTL)."""

    def __init__(self, db: AsyncSession) -> None:
        self.db = db

    async def get(self, query: str) -> dict | None:
        """Look up cached result. Returns None if miss or expired."""
        query_hash = hash_query(query)
        now = datetime.now(timezone.utc)

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

    async def set(self, query: str, payload: dict) -> None:
        """Insert or update cache entry with 24h TTL."""
        query_hash = hash_query(query)
        normalized = normalize_query(query)
        now = datetime.now(timezone.utc)
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
                "raw": normalized,
                "payload": json.dumps(payload),
                "now": now,
                "expires": expires,
            },
        )
        await self.db.flush()
        logger.info("search_cache.set", query_hash=query_hash[:12])
