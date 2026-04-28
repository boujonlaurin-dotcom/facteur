"""Probe the external search pipeline (Brave + root-host fallback + denylist)
on a list of FR queries that are intentionally NOT in the catalogue, to
measure how many resolve to a real RSS-bearing source after the
2026-04-26 refactor.

Usage:
    BRAVE_API_KEY=... python scripts/probe_external_search.py

Bypasses the DB entirely — it instantiates BraveSearchProvider, GoogleNews
provider, and RSSParser directly, mirrors the orchestrator's filtering, and
prints a per-query report.
"""

import asyncio
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.services.rss_parser import RSSParser  # noqa: E402
from app.services.search.providers.brave import BraveSearchProvider  # noqa: E402
from app.services.search.providers.denylist import (  # noqa: E402
    is_listicle_host,
    is_listicle_title,
)
from app.services.search.providers.google_news import GoogleNewsProvider  # noqa: E402

QUERIES = [
    "politis",
    "disclose",
    "le media",
    "frustration magazine",
    "mediacites",
    # Sanity controls:
    "hugo decrypte",
    "the generalist",
    "arret sur images",
    # Cas listicle: doit retourner peu/zéro après le filtre.
    "political news",
]


def _root_url(url: str) -> str | None:
    from urllib.parse import urlparse

    try:
        p = urlparse(url)
    except ValueError:
        return None
    if not p.scheme or not p.netloc:
        return None
    return f"{p.scheme}://{p.netloc}"


FEED_DETECT_TIMEOUT_S = 4.0


_PATH_LEVEL_PLATFORMS = frozenset(
    {
        "www.youtube.com",
        "youtube.com",
        "m.youtube.com",
        "substack.com",
        "medium.com",
    }
)


async def _detect(rss: RSSParser, url: str) -> tuple[str, dict] | None:
    """Mirror orchestrator's _detect_with_root_fallback (root-only)."""
    from urllib.parse import urlparse as _u

    host = (_u(url).netloc or "").lower()
    root = _root_url(url)
    target = root if root and host not in _PATH_LEVEL_PLATFORMS else url
    try:
        det = await asyncio.wait_for(rss.detect(target), timeout=FEED_DETECT_TIMEOUT_S)
        if det.feed_url:
            return target, {"feed_url": det.feed_url, "title": det.title}
    except (TimeoutError, Exception):
        pass
    return None


async def _detect_with_short_circuit(
    rss: RSSParser, urls: list[str]
) -> list[tuple[int, tuple[str, dict]]]:
    """Mirror orchestrator: parallel detection, stop at 3 hits or 1.5s after first."""

    async def _resolve(idx: int, url: str):
        return idx, await _detect(rss, url)

    tasks = [asyncio.create_task(_resolve(i, u)) for i, u in enumerate(urls)]
    collected: list[tuple[int, tuple[str, dict]]] = []
    loop = asyncio.get_event_loop()
    first_hit_at: float | None = None
    GRACE = 1.5
    try:
        pending = set(tasks)
        while pending:
            timeout = (
                None
                if first_hit_at is None
                else max(0.0, GRACE - (loop.time() - first_hit_at))
            )
            done, pending = await asyncio.wait(
                pending, return_when=asyncio.FIRST_COMPLETED, timeout=timeout
            )
            if not done:
                break
            for d in done:
                try:
                    idx, det = d.result()
                except Exception:
                    continue
                if det is None:
                    continue
                collected.append((idx, det))
                if first_hit_at is None:
                    first_hit_at = loop.time()
            if len(collected) >= 3:
                break
    finally:
        for t in tasks:
            if not t.done():
                t.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
    collected.sort(key=lambda x: x[0])
    return collected


_FRENCH_HINT_TOKENS = {
    "le",
    "la",
    "les",
    "de",
    "du",
    "des",
    "et",
    "actu",
    "actus",
    "actualite",
    "actualites",
    "journal",
    "magazine",
    "presse",
    "info",
    "infos",
    "media",
    "medias",
}


def _looks_french(query: str) -> bool:
    if any(c in query for c in "àâäéèêëîïôöùûüÿç"):
        return True
    tokens = query.lower().split()
    return any(t in _FRENCH_HINT_TOKENS for t in tokens)


async def probe_brave(brave: BraveSearchProvider, rss: RSSParser, q: str) -> dict:
    from urllib.parse import urlparse as _u

    t0 = time.monotonic()
    raw = await brave.search(q, count=8)
    raw_candidates: list[tuple[str, str]] = []
    for r in raw[:8]:
        url = r.get("url", "")
        title = r.get("title", "")
        if not url:
            continue
        if is_listicle_host(url) or is_listicle_title(title):
            continue
        raw_candidates.append((url, title))

    host_counts: dict[str, int] = {}
    for url, _ in raw_candidates:
        host = (_u(url).netloc or "").lower()
        host_counts[host] = host_counts.get(host, 0) + 1
    prefer_fr = _looks_french(q)

    def _score(item):
        url, _ = item
        host = (_u(url).netloc or "").lower()
        return (
            1 if (prefer_fr and host.endswith(".fr")) else 0,
            host_counts.get(host, 0),
        )

    ranked = sorted(raw_candidates, key=_score, reverse=True)
    candidates = ranked[:5]

    collected = await _detect_with_short_circuit(rss, [u for u, _ in candidates])
    final = [
        {"url": det[0], "feed_url": det[1]["feed_url"], "title": det[1]["title"]}
        for _, det in collected
    ]
    return {
        "query": q,
        "brave_raw_count": len(raw),
        "after_listicle": [u for u, _ in candidates],
        "final": final,
        "latency_ms": int((time.monotonic() - t0) * 1000),
    }


async def probe_gnews(gnews: GoogleNewsProvider, rss: RSSParser, q: str) -> dict:
    t0 = time.monotonic()
    raw = await gnews.search(q, limit=8)
    kept = [u for u in raw[:8] if u and not is_listicle_host(u)][:5]
    collected = await _detect_with_short_circuit(rss, kept)
    final = [
        {"url": det[0], "feed_url": det[1]["feed_url"], "title": det[1]["title"]}
        for _, det in collected
    ]
    return {
        "query": q,
        "gnews_raw_count": len(raw),
        "kept_hosts": kept,
        "final": final,
        "latency_ms": int((time.monotonic() - t0) * 1000),
    }


async def main() -> int:
    if not os.getenv("BRAVE_API_KEY"):
        print("BRAVE_API_KEY missing — set it before running.", file=sys.stderr)
        return 2

    brave = BraveSearchProvider()
    gnews = GoogleNewsProvider()
    rss = RSSParser()

    print("\n=== Brave ===")
    for q in QUERIES:
        out = await probe_brave(brave, rss, q)
        feeds = [f["feed_url"] for f in out["final"]]
        print(
            f"[{out['latency_ms']:>5} ms] {q!r:30}"
            f"  raw={out['brave_raw_count']:>2}"
            f"  kept={len(out['after_listicle']):>1}"
            f"  feeds={len(feeds):>1}  -> {feeds[:3]}"
        )

    print("\n=== Google News ===")
    for q in QUERIES:
        out = await probe_gnews(gnews, rss, q)
        feeds = [f["feed_url"] for f in out["final"]]
        print(
            f"[{out['latency_ms']:>5} ms] {q!r:30}"
            f"  hosts={len(out['kept_hosts']):>1}"
            f"  feeds={len(feeds):>1}  -> {feeds[:3]}"
        )

    await rss.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
