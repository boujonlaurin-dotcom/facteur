"""
Story 12.2 — Rescue des sources échouées (read-only prod)

Étend le pattern de ``analyze_failed_sources.py`` (Supabase PostgREST, service
role) SANS le dupliquer : collecte l'union dédupliquée de
``failed_source_attempts`` + ``source_search_logs`` (result_count=0 OU
abandoned) sur une fenêtre paramétrable (défaut 90 j), rejoue la résolution
offline avec un budget large (``detect()`` timeouts élargis + curl-cffi ;
reddit ``r/<sub>`` direct), classe chaque signal via
``app.services.rescue.classify_signal`` (source unique, partagée avec le job
hebdo), et écrit :
  * ``docs/maintenance/diag-rescue-failed-sources.md``
  * ``.context/rescue-results.json``

Le classement N'AJOUTE JAMAIS de source : lecture seule.

Usage :
  SUPABASE_URL=https://xxx.supabase.co \
  SUPABASE_SERVICE_ROLE_KEY=xxx \
  python scripts/rescue_failed_sources.py [--days 90] [--no-resolve]
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
from datetime import UTC, datetime, timedelta

import httpx

# Rendre l'app importable quand le script est lancé depuis packages/api.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.services.rescue import (  # noqa: E402
    CATEGORIES,
    Signal,
    classify_all,
    infer_abandons,
    is_url_like,
    merge_signal,
    summarize,
)

# Cap sur les résolutions réseau vivantes (comme le job hebdo).
_MAX_RESOLUTIONS = 80
_RESOLVE_TIMEOUT_S = 12.0


def _parse_ts(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=UTC)


async def _rest_get(
    client: httpx.AsyncClient, base: str, path: str, params: dict
) -> list[dict]:
    resp = await client.get(f"{base}/rest/v1/{path}", params=params)
    resp.raise_for_status()
    return resp.json()


async def collect_via_rest(base: str, key: str, days: int) -> tuple[list[Signal], dict]:
    """Fetch + dedupe signals over the window; also return abandon-inference data."""
    cutoff = (datetime.now(UTC) - timedelta(days=days)).isoformat()
    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
    }
    signals: dict[str, Signal] = {}
    async with httpx.AsyncClient(timeout=30.0, headers=headers) as client:
        attempts = await _rest_get(
            client,
            base,
            "failed_source_attempts",
            {
                "select": "user_id,input_text,input_type,created_at",
                "created_at": f"gte.{cutoff}",
                "limit": "2000",
            },
        )
        for row in attempts:
            text = (row.get("input_text") or "").strip()
            if not text:
                continue
            merge_signal(
                signals,
                input_text=text,
                kind="url" if is_url_like(text) else "keyword",
                user_id=row.get("user_id"),
            )

        zero_or_abandoned = await _rest_get(
            client,
            base,
            "source_search_logs",
            {
                "select": "user_id,query_raw,content_type,result_count,abandoned,created_at",
                "created_at": f"gte.{cutoff}",
                "or": "(result_count.eq.0,abandoned.eq.true)",
                "limit": "2000",
            },
        )
        for row in zero_or_abandoned:
            text = (row.get("query_raw") or "").strip()
            if not text:
                continue
            merge_signal(
                signals,
                input_text=text,
                kind="url" if is_url_like(text) else "keyword",
                content_type=row.get("content_type"),
                result_count=row.get("result_count") or 0,
                abandoned=bool(row.get("abandoned")),
                user_id=row.get("user_id"),
            )

        # Données pour l'inférence d'abandon (T0.4b) : searches AVEC résultats.
        result_logs_raw = await _rest_get(
            client,
            base,
            "source_search_logs",
            {
                "select": "user_id,query_normalized,result_count,created_at",
                "created_at": f"gte.{cutoff}",
                "result_count": "gt.0",
                "limit": "5000",
            },
        )
        adds_raw = await _rest_get(
            client,
            base,
            "user_sources",
            {
                "select": "user_id,added_at",
                "added_at": f"gte.{cutoff}",
                "limit": "5000",
            },
        )

    result_logs = [
        {
            "user_id": r.get("user_id"),
            "created_at": _parse_ts(r.get("created_at")),
            "query_normalized": r.get("query_normalized"),
        }
        for r in result_logs_raw
        if _parse_ts(r.get("created_at"))
    ]
    adds = [
        {"user_id": r.get("user_id"), "added_at": _parse_ts(r.get("added_at"))}
        for r in adds_raw
        if _parse_ts(r.get("added_at"))
    ]
    return list(signals.values()), {"result_logs": result_logs, "adds": adds}


def _make_resolver(max_resolutions: int):
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


def render_report(
    days: int, classified: list[dict], summary: dict, inferred: int
) -> str:
    lines: list[str] = []
    lines.append("# Rescue des sources échouées — Story 12.2\n")
    lines.append(f"**Date** : {datetime.now(UTC).strftime('%Y-%m-%d')}")
    lines.append(f"**Fenêtre** : {days} derniers jours")
    lines.append("**Mode** : lecture seule (aucune source ajoutée)\n")
    lines.append("---\n")

    lines.append("## Compteurs par catégorie\n")
    lines.append("| Catégorie | Count |")
    lines.append("|-----------|-------|")
    for cat in CATEGORIES:
        lines.append(f"| {cat} | {summary['by_category'].get(cat, 0)} |")
    lines.append(f"| **Total signaux** | **{summary['total']}** |")
    lines.append("")
    lines.append(
        f"**`no_feed` hôtes distincts (signal de gating Palier 2)** : "
        f"{summary['no_feed_host_count']}"
    )
    lines.append(
        f"**Abandons inférés (searches avec résultats, sans add)** : {inferred}\n"
    )

    if summary["no_feed_hosts"]:
        lines.append("### Hôtes `no_feed` (candidats Palier 2)\n")
        for host in summary["no_feed_hosts"]:
            lines.append(f"- `{host}`")
        lines.append("")

    lines.append("## Détail des signaux\n")
    lines.append(
        "| Input | Kind | Type | Occ. | Résultats | Abandon | Résoluble | Catégorie |"
    )
    lines.append(
        "|-------|------|------|------|-----------|---------|-----------|-----------|"
    )
    for row in sorted(classified, key=lambda r: r["category"]):
        lines.append(
            f"| `{row['input_text'][:48]}` | {row['kind']} | "
            f"{row.get('content_type') or '-'} | {row['occurrences']} | "
            f"{row['max_result_count']} | {row['abandoned']} | "
            f"{row['resolvable']} | {row['category']} |"
        )
    lines.append("")
    lines.append("---\n")
    lines.append("*Généré par scripts/rescue_failed_sources.py (Story 12.2).*")
    return "\n".join(lines)


async def main() -> None:
    parser = argparse.ArgumentParser(description="Rescue failed source adds")
    parser.add_argument("--days", type=int, default=90)
    parser.add_argument(
        "--no-resolve",
        action="store_true",
        help="Classe sur la métadonnée seule (aucun detect() réseau)",
    )
    args = parser.parse_args()

    base = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if not base or not key:
        print("ERROR: set SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY", file=sys.stderr)
        sys.exit(1)

    print(f"Collecting signals over the last {args.days} days…")
    signals, abandon_data = await collect_via_rest(base, key, args.days)
    print(f"  {len(signals)} distinct signals")

    resolver = None if args.no_resolve else _make_resolver(_MAX_RESOLUTIONS)
    classified = await classify_all(signals, resolver)
    summary = summarize(classified)
    inferred = len(infer_abandons(abandon_data["result_logs"], abandon_data["adds"]))

    report = render_report(args.days, classified, summary, inferred)

    api_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    repo_root = os.path.dirname(os.path.dirname(api_root))
    md_path = os.path.join(
        repo_root, "docs", "maintenance", "diag-rescue-failed-sources.md"
    )
    json_path = os.path.join(repo_root, ".context", "rescue-results.json")
    os.makedirs(os.path.dirname(json_path), exist_ok=True)

    with open(md_path, "w") as f:
        f.write(report)
    with open(json_path, "w") as f:
        json.dump(
            {
                "generated_at": datetime.now(UTC).isoformat(),
                "days": args.days,
                "summary": summary,
                "inferred_abandons": inferred,
                "signals": classified,
            },
            f,
            indent=2,
            ensure_ascii=False,
        )

    print(f"\nReport : {md_path}")
    print(f"JSON   : {json_path}")
    print(f"\nBy category: {summary['by_category']}")
    print(f"no_feed hosts (Palier 2 gate): {summary['no_feed_host_count']}")


if __name__ == "__main__":
    asyncio.run(main())
