"""Offline CTR gauge for digest/feed ranking.

The script reads persisted ``daily_digest.items`` and joins them with
``user_content_status`` plus ``contents``. It reports CTR by topic, entity,
rank, and pillar score band.

Usage:
    cd packages/api
    PYTHONPATH=. python scripts/evaluate_feed_ranking.py --days 14
"""

from __future__ import annotations

import argparse
import asyncio
import datetime as dt
import json
import os
import sys
from collections import defaultdict
from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

REPO_ROOT = Path(__file__).resolve().parents[3]
CONTEXT_DIR = REPO_ROOT / ".context"

PILLARS = ("pertinence", "source", "fraicheur", "qualite")


@dataclass
class CtrBucket:
    shown: int = 0
    consumed: int = 0

    def add(self, *, consumed: bool) -> None:
        self.shown += 1
        if consumed:
            self.consumed += 1

    @property
    def ctr(self) -> float:
        if self.shown == 0:
            return 0.0
        return self.consumed / self.shown


def _load_env_file(path: Path) -> None:
    if not path.exists():
        return
    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if key and key not in os.environ:
            os.environ[key] = value.strip().strip('"').strip("'")


def _database_url() -> str:
    _load_env_file(REPO_ROOT / "packages" / "api" / ".env")
    _load_env_file(REPO_ROOT / ".env")

    url = os.environ.get("DATABASE_URL")
    if not url:
        raise SystemExit("DATABASE_URL is required")
    if url.startswith("postgres://"):
        return "postgresql+psycopg://" + url.removeprefix("postgres://")
    if url.startswith("postgresql://"):
        return "postgresql+psycopg://" + url.removeprefix("postgresql://")
    return url


def _parse_date(value: str | None) -> dt.datetime | None:
    if not value:
        return None
    parsed = dt.datetime.fromisoformat(value)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.UTC)
    return parsed.astimezone(dt.UTC)


def _coerce_json_object(value: Any) -> dict[str, Any]:
    if isinstance(value, dict):
        return value
    if isinstance(value, str) and value.strip():
        try:
            parsed = json.loads(value)
        except json.JSONDecodeError:
            return {}
        return parsed if isinstance(parsed, dict) else {}
    return {}


def _entity_name(raw: Any) -> str | None:
    value = raw
    if isinstance(raw, str):
        stripped = raw.strip()
        if not stripped:
            return None
        if stripped.startswith("{"):
            try:
                value = json.loads(stripped)
            except json.JSONDecodeError:
                value = stripped
        else:
            value = stripped

    if isinstance(value, dict):
        name = (
            value.get("canonical")
            or value.get("canonical_name")
            or value.get("name")
            or value.get("text")
        )
    else:
        name = value

    if not isinstance(name, str):
        return None
    normalized = " ".join(name.strip().split())
    return normalized or None


def _entity_names(raw_entities: Iterable[Any] | None) -> list[str]:
    seen: set[str] = set()
    names: list[str] = []
    for raw in raw_entities or []:
        name = _entity_name(raw)
        if not name:
            continue
        key = name.casefold()
        if key in seen:
            continue
        seen.add(key)
        names.append(name)
    return names


def _topic_slugs(raw_topics: Iterable[Any] | None) -> list[str]:
    seen: set[str] = set()
    topics: list[str] = []
    for raw in raw_topics or []:
        if not isinstance(raw, str):
            continue
        topic = raw.strip().lower()
        if not topic or topic in seen:
            continue
        seen.add(topic)
        topics.append(topic)
    return topics


def _score_band(score: Any, step: int = 20) -> str:
    if not isinstance(score, int | float):
        return "missing"
    if score < 0:
        return "<0"
    if score >= 100:
        return "100+"
    low = int(score // step) * step
    return f"{low:02d}-{low + step:02d}"


def _pct(value: float) -> str:
    return f"{value * 100:.1f}%"


def _format_rows(
    rows: list[tuple[str, CtrBucket]],
    *,
    key_label: str,
    min_shown: int,
    top: int | None = None,
) -> list[str]:
    filtered = [(label, bucket) for label, bucket in rows if bucket.shown >= min_shown]
    if top is not None:
        filtered = filtered[:top]
    if not filtered:
        return ["_No rows above threshold._"]

    lines = [
        f"| {key_label} | shown | consumed | CTR |",
        f"| {'-' * len(key_label)} | ---: | ---: | ---: |",
    ]
    for label, bucket in filtered:
        lines.append(
            f"| {label} | {bucket.shown} | {bucket.consumed} | {_pct(bucket.ctr)} |"
        )
    return lines


def _build_report(
    *,
    rows: list[dict[str, Any]],
    since: dt.datetime,
    until: dt.datetime,
    mode: str | None,
    include_serene: bool,
    min_shown: int,
    top: int,
) -> str:
    global_bucket = CtrBucket()
    by_rank: defaultdict[int, CtrBucket] = defaultdict(CtrBucket)
    by_topic: defaultdict[str, CtrBucket] = defaultdict(CtrBucket)
    by_entity: defaultdict[str, CtrBucket] = defaultdict(CtrBucket)
    by_pillar_band: dict[str, defaultdict[str, CtrBucket]] = {
        pillar: defaultdict(CtrBucket) for pillar in PILLARS
    }

    skipped_unshown = 0
    shown_digest_ids: set[str] = set()
    shown_user_ids: set[str] = set()

    for row in rows:
        status = str(row.get("status") or "").lower()
        consumed = status == "consumed"
        shown = row.get("last_impressed_at") is not None or consumed
        if not shown:
            skipped_unshown += 1
            continue

        global_bucket.add(consumed=consumed)
        shown_digest_ids.add(str(row.get("digest_id")))
        shown_user_ids.add(str(row.get("user_id")))

        rank = row.get("rank")
        if isinstance(rank, int):
            by_rank[rank].add(consumed=consumed)

        for topic in _topic_slugs(row.get("topics")):
            by_topic[topic].add(consumed=consumed)

        for entity in _entity_names(row.get("entities")):
            by_entity[entity].add(consumed=consumed)

        pillar_scores = _coerce_json_object(row.get("pillar_scores"))
        for pillar in PILLARS:
            band = _score_band(pillar_scores.get(pillar))
            by_pillar_band[pillar][band].add(consumed=consumed)

    generated_at = dt.datetime.now(dt.UTC).strftime("%Y-%m-%d %H:%M:%SZ")
    lines = [
        f"# Feed Ranking CTR Gauge - {generated_at}",
        "",
        f"- Window: {since.isoformat()} -> {until.isoformat()}",
        f"- Mode: {mode or 'all'}",
        f"- Includes serene digests: {'yes' if include_serene else 'no'}",
        f"- Rows fetched: {len(rows)}",
        f"- Rows skipped because not shown: {skipped_unshown}",
        f"- Shown digests: {len(shown_digest_ids)}",
        f"- Users with shown items: {len(shown_user_ids)}",
        f"- Global CTR: {global_bucket.consumed}/{global_bucket.shown} = {_pct(global_bucket.ctr)}",
        "",
        "## CTR by Rank",
        "",
    ]

    rank_rows = [
        (str(rank), bucket)
        for rank, bucket in sorted(by_rank.items(), key=lambda x: x[0])
    ]
    lines.extend(
        _format_rows(rank_rows, key_label="rank", min_shown=min_shown, top=None)
    )

    lines.extend(["", "## CTR by Topic", ""])
    topic_rows = sorted(by_topic.items(), key=lambda x: (-x[1].shown, -x[1].ctr, x[0]))
    lines.extend(
        _format_rows(topic_rows, key_label="topic", min_shown=min_shown, top=top)
    )

    lines.extend(["", "## CTR by Entity", ""])
    entity_rows = sorted(
        by_entity.items(), key=lambda x: (-x[1].shown, -x[1].ctr, x[0].casefold())
    )
    lines.extend(
        _format_rows(entity_rows, key_label="entity", min_shown=min_shown, top=top)
    )

    lines.extend(["", "## CTR by Pillar Score Band", ""])
    for pillar in PILLARS:
        lines.extend([f"### {pillar.capitalize()}", ""])
        band_rows = sorted(
            by_pillar_band[pillar].items(),
            key=lambda x: (x[0] == "missing", x[0]),
        )
        lines.extend(
            _format_rows(band_rows, key_label="score band", min_shown=1, top=None)
        )
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


SQL = """
WITH flat_items AS (
    SELECT
        dd.id AS digest_id,
        dd.user_id,
        dd.target_date,
        dd.generated_at,
        dd.mode,
        dd.is_serene,
        item AS item_json,
        NULL::integer AS topic_rank
    FROM daily_digest dd
    CROSS JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN jsonb_typeof(dd.items) = 'array' THEN dd.items
            ELSE '[]'::jsonb
        END
    ) AS item
    WHERE dd.generated_at >= :since
      AND dd.generated_at < :until
      AND (:mode IS NULL OR dd.mode = :mode)
      AND (:include_serene OR dd.is_serene = false)
),
topic_items AS (
    SELECT
        dd.id AS digest_id,
        dd.user_id,
        dd.target_date,
        dd.generated_at,
        dd.mode,
        dd.is_serene,
        article_item AS item_json,
        NULLIF(topic_item->>'rank', '')::integer AS topic_rank
    FROM daily_digest dd
    CROSS JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN jsonb_typeof(dd.items) = 'object'
                THEN COALESCE(dd.items->'topics', '[]'::jsonb)
            ELSE '[]'::jsonb
        END
    ) AS topic_item
    CROSS JOIN LATERAL jsonb_array_elements(
        COALESCE(topic_item->'articles', '[]'::jsonb)
    ) AS article_item
    WHERE dd.generated_at >= :since
      AND dd.generated_at < :until
      AND (:mode IS NULL OR dd.mode = :mode)
      AND (:include_serene OR dd.is_serene = false)
),
digest_items AS (
    SELECT * FROM flat_items
    UNION ALL
    SELECT * FROM topic_items
),
parsed_items AS (
    SELECT
        digest_id,
        user_id,
        target_date,
        generated_at,
        mode,
        is_serene,
        NULLIF(item_json->>'content_id', '') AS content_id_text,
        COALESCE(NULLIF(item_json->>'rank', '')::integer, topic_rank) AS rank,
        COALESCE(
            NULLIF(item_json->>'final_score', '')::double precision,
            NULLIF(item_json->>'score', '')::double precision
        ) AS final_score,
        COALESCE(item_json->'pillar_scores', '{}'::jsonb) AS pillar_scores
    FROM digest_items
    WHERE item_json ? 'content_id'
)
SELECT
    pi.digest_id,
    pi.user_id,
    pi.target_date,
    pi.generated_at,
    pi.mode,
    pi.is_serene,
    pi.content_id_text::uuid AS content_id,
    pi.rank,
    pi.final_score,
    pi.pillar_scores,
    ucs.status::text AS status,
    ucs.last_impressed_at,
    c.topics,
    c.entities
FROM parsed_items pi
JOIN contents c ON c.id = pi.content_id_text::uuid
LEFT JOIN user_content_status ucs
    ON ucs.user_id = pi.user_id
   AND ucs.content_id = pi.content_id_text::uuid
ORDER BY pi.generated_at DESC, pi.rank NULLS LAST
LIMIT :row_limit
"""


async def _fetch_rows(args: argparse.Namespace) -> list[dict[str, Any]]:
    url = _database_url()
    connect_args: dict[str, Any] = {}
    if "+psycopg" in url:
        connect_args["prepare_threshold"] = None

    engine = create_async_engine(url, pool_pre_ping=False, connect_args=connect_args)
    try:
        async with engine.connect() as conn:
            result = await conn.execute(
                text(SQL),
                {
                    "since": args.since,
                    "until": args.until,
                    "mode": args.mode,
                    "include_serene": args.include_serene,
                    "row_limit": args.row_limit,
                },
            )
            return [dict(row._mapping) for row in result.fetchall()]
    finally:
        await engine.dispose()


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--days", type=int, default=14, help="Lookback window in days")
    parser.add_argument("--since", help="UTC ISO datetime/date lower bound")
    parser.add_argument("--until", help="UTC ISO datetime/date upper bound")
    parser.add_argument("--mode", help="Filter daily_digest.mode")
    parser.add_argument(
        "--include-serene",
        action="store_true",
        help="Include serene digest variants",
    )
    parser.add_argument("--min-shown", type=int, default=5)
    parser.add_argument("--top", type=int, default=25)
    parser.add_argument("--row-limit", type=int, default=20000)
    parser.add_argument("--tag", default="latest")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--no-write", action="store_true")
    args = parser.parse_args(argv)

    now = dt.datetime.now(dt.UTC)
    args.until = _parse_date(args.until) or now
    args.since = _parse_date(args.since) or (args.until - dt.timedelta(days=args.days))
    if args.since >= args.until:
        raise SystemExit("--since must be earlier than --until")
    return args


async def _main(argv: list[str]) -> int:
    args = _parse_args(argv)
    rows = await _fetch_rows(args)
    report = _build_report(
        rows=rows,
        since=args.since,
        until=args.until,
        mode=args.mode,
        include_serene=args.include_serene,
        min_shown=args.min_shown,
        top=args.top,
    )
    print(report)

    if not args.no_write:
        CONTEXT_DIR.mkdir(parents=True, exist_ok=True)
        timestamp = dt.datetime.now(dt.UTC).strftime("%Y%m%d-%H%M%S")
        output = args.output or CONTEXT_DIR / f"feed-ranking-{args.tag}-{timestamp}.md"
        output.write_text(report)
        print(f"Wrote {output}")

    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(_main(sys.argv[1:])))
