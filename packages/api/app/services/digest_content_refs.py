"""Helpers to extract content_id references from DailyDigest JSONB payloads.

The digest is stored in 3 possible layouts, depending on `format_version`:

- **flat_v1**: ``items`` is a JSON *array* of ``{"content_id": ..., ...}``.
- **topics_v1**: ``items`` is a JSON *object*
  ``{"format": "topics_v1", "topics": [{"articles": [{"content_id": ...}, ...]}, ...]}``.
- **editorial_v1**: ``items`` is a JSON *object* with structured keys:
  ``subjects[i].actu_article.content_id``,
  ``subjects[i].extra_actu_articles[j].content_id``,
  ``subjects[i].deep_article.content_id``,
  plus top-level ``pepite.content_id``, ``coup_de_coeur.content_id``,
  ``actu_decalee.content_id``.

Any code that needs to know which Content rows are still referenced by live
digests (e.g. the RSS storage cleanup worker, or the diag endpoint) should
use these helpers instead of re-implementing the layout walk.
"""

from __future__ import annotations

from typing import Any
from uuid import UUID


def _safe_uuid(value: Any) -> UUID | None:
    """Parse ``value`` as UUID, returning None on any error."""
    if not value:
        return None
    try:
        return UUID(str(value))
    except (ValueError, TypeError, AttributeError):
        return None


def extract_content_ids(items: Any, format_version: str | None) -> set[UUID]:
    """Return every content_id referenced by a digest's ``items`` payload.

    Tolerates malformed payloads (missing keys, None entries, bad UUIDs):
    anything unparseable is silently skipped — the caller only wants "what
    IDs does this digest legitimately reference?", not validation.
    """
    ids: set[UUID] = set()
    if items is None:
        return ids

    fmt = format_version or "flat_v1"

    if fmt == "editorial_v1" and isinstance(items, dict):
        for subject in items.get("subjects") or []:
            if not isinstance(subject, dict):
                continue
            actu = subject.get("actu_article")
            if isinstance(actu, dict):
                if (cid := _safe_uuid(actu.get("content_id"))) is not None:
                    ids.add(cid)
            for extra in subject.get("extra_actu_articles") or []:
                if isinstance(extra, dict):
                    if (cid := _safe_uuid(extra.get("content_id"))) is not None:
                        ids.add(cid)
            deep = subject.get("deep_article")
            if isinstance(deep, dict):
                if (cid := _safe_uuid(deep.get("content_id"))) is not None:
                    ids.add(cid)
        for key in ("pepite", "coup_de_coeur", "actu_decalee"):
            node = items.get(key)
            if isinstance(node, dict):
                if (cid := _safe_uuid(node.get("content_id"))) is not None:
                    ids.add(cid)
        return ids

    if fmt == "topics_v1" and isinstance(items, dict):
        for topic in items.get("topics") or []:
            if not isinstance(topic, dict):
                continue
            for art in topic.get("articles") or []:
                if isinstance(art, dict):
                    if (cid := _safe_uuid(art.get("content_id"))) is not None:
                        ids.add(cid)
        return ids

    # flat_v1 (and unknown legacy formats): items is an array
    if isinstance(items, list):
        for item in items:
            if isinstance(item, dict):
                if (cid := _safe_uuid(item.get("content_id"))) is not None:
                    ids.add(cid)
    return ids
