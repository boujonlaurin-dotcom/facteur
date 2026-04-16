"""Probe harness : run RSSParser.detect() against top FR mainstream sites.

Since failed_source_attempts in prod is empty (see docs/bugs/
bug-failed-source-attempts-logging.md) and Sentry records zero matching
ValueErrors (because FastAPI swallows HTTPException before Sentry), we
build a *synthetic* dataset of the URLs users are most likely to paste
and test each one against the live detection pipeline.

Output : docs/maintenance/failed-sources-dataset.md
         + stdout CSV for quick grep

Usage (from repo root):
    python packages/api/scripts/probe_failed_sources.py

Requires httpx, feedparser, beautifulsoup4, curl-cffi, lxml, pydantic-settings.
"""

from __future__ import annotations

import asyncio
import csv
import io
import sys
import time
from pathlib import Path

# Make `app.*` imports resolvable no matter where this script is run from
_PACKAGES_API = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_PACKAGES_API))

from app.services.rss_parser import RSSParser  # noqa: E402

# Top French mainstream news/media bare domains : what a non-technical user
# is most likely to paste into "Add a source". Mix of hard cases (anti-bot,
# non-standard feed paths) and easy ones (WordPress-like).
TEST_URLS: list[tuple[str, str]] = [
    # Mainstream national press (hardest — anti-bot + custom feed paths)
    ("L'Équipe", "https://www.lequipe.fr/"),
    ("Le Monde", "https://www.lemonde.fr/"),
    ("Le Figaro", "https://www.lefigaro.fr/"),
    ("Le Parisien", "https://www.leparisien.fr/"),
    ("Libération", "https://www.liberation.fr/"),
    ("Les Echos", "https://www.lesechos.fr/"),
    ("La Croix", "https://www.la-croix.com/"),
    ("L'Humanité", "https://www.humanite.fr/"),
    ("Mediapart", "https://www.mediapart.fr/"),
    ("L'Obs", "https://www.nouvelobs.com/"),
    ("Le Point", "https://www.lepoint.fr/"),
    ("L'Express", "https://www.lexpress.fr/"),
    ("Marianne", "https://www.marianne.net/"),
    ("Charlie Hebdo", "https://charliehebdo.fr/"),
    ("Courrier International", "https://www.courrierinternational.com/"),
    # Broadcast / radio
    ("France Info", "https://www.francetvinfo.fr/"),
    ("France Inter", "https://www.radiofrance.fr/franceinter"),
    ("France Culture", "https://www.radiofrance.fr/franceculture"),
    ("BFMTV", "https://www.bfmtv.com/"),
    ("TF1 Info", "https://www.tf1info.fr/"),
    # Regional
    ("Ouest France", "https://www.ouest-france.fr/"),
    ("Sud Ouest", "https://www.sudouest.fr/"),
    ("La Dépêche", "https://www.ladepeche.fr/"),
    ("20 Minutes", "https://www.20minutes.fr/"),
    # Culture / specialised
    ("Télérama", "https://www.telerama.fr/"),
    ("Slate", "https://www.slate.fr/"),
    ("Konbini", "https://www.konbini.com/fr/"),
    ("Numerama", "https://www.numerama.com/"),
    ("Next INpact", "https://next.ink/"),
    ("Korii", "https://korii.slate.fr/"),
]


async def probe_one(parser: RSSParser, name: str, url: str) -> dict:
    """Run detect() on one URL, capture full outcome."""
    t0 = time.monotonic()
    result: dict = {
        "name": name,
        "url": url,
        "success": False,
        "feed_url": "",
        "feed_type": "",
        "entries": 0,
        "error": "",
        "stages": "",
        "latency_ms": 0,
    }
    try:
        detected = await asyncio.wait_for(parser.detect(url), timeout=30.0)
        result["success"] = True
        result["feed_url"] = detected.feed_url
        result["feed_type"] = detected.feed_type
        result["entries"] = len(detected.entries)
    except ValueError as e:
        msg = str(e)
        result["error"] = msg[:500]
        # The parser appends "Tried: ..." to its ValueError — extract stage log
        if "Tried:" in msg:
            result["stages"] = msg.split("Tried:", 1)[1].strip()[:500]
    except asyncio.TimeoutError:
        result["error"] = "TIMEOUT_30s"
    except Exception as e:  # noqa: BLE001
        result["error"] = f"{type(e).__name__}: {e}"[:500]
    finally:
        result["latency_ms"] = int((time.monotonic() - t0) * 1000)
    return result


async def main() -> int:
    parser = RSSParser()
    try:
        # Run sequentially to keep logs readable and avoid hammering one host
        results: list[dict] = []
        for name, url in TEST_URLS:
            print(f"→ {name}  ({url})", flush=True)
            r = await probe_one(parser, name, url)
            status = "OK" if r["success"] else "FAIL"
            tail = (
                f"feed={r['feed_url']}"
                if r["success"]
                else f"err={r['error'][:120]}"
            )
            print(f"  {status}  {r['latency_ms']}ms  {tail}", flush=True)
            results.append(r)
    finally:
        await parser.close()

    _emit_csv(results)
    _emit_markdown(results)
    return 0


def _emit_csv(results: list[dict]) -> None:
    buf = io.StringIO()
    writer = csv.DictWriter(
        buf,
        fieldnames=[
            "name",
            "url",
            "success",
            "feed_url",
            "feed_type",
            "entries",
            "latency_ms",
            "error",
            "stages",
        ],
    )
    writer.writeheader()
    writer.writerows(results)
    out_csv = Path("docs/maintenance/failed-sources-dataset.csv")
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    out_csv.write_text(buf.getvalue(), encoding="utf-8")
    print(f"\nCSV written → {out_csv}")


def _emit_markdown(results: list[dict]) -> None:
    n_ok = sum(1 for r in results if r["success"])
    n_total = len(results)
    lines: list[str] = []
    lines.append("# Failed sources — synthetic probe dataset")
    lines.append("")
    lines.append(
        "Top French mainstream news/media domains tested against "
        "`RSSParser.detect()` on current `main`. Since the real "
        "`failed_source_attempts` table is empty (logging bug, see "
        "`docs/bugs/bug-failed-source-attempts-logging.md`), this "
        "synthetic dataset plays the same role."
    )
    lines.append("")
    lines.append(f"**Résultat : {n_ok}/{n_total} détectés** "
                 f"({100 * n_ok // n_total}%).")
    lines.append("")
    lines.append("## Tableau")
    lines.append("")
    lines.append("| # | Source | Succès | Feed URL / Erreur | Stages |")
    lines.append("|---|---|---|---|---|")
    for i, r in enumerate(results, 1):
        ok = "✅" if r["success"] else "❌"
        detail = r["feed_url"] if r["success"] else f"`{r['error'][:80]}`"
        stages = f"`{r['stages'][:80]}`" if r["stages"] else "—"
        lines.append(f"| {i} | **{r['name']}** | {ok} | {detail} | {stages} |")
    lines.append("")
    lines.append("## Patterns d'échec")
    lines.append("")
    failures = [r for r in results if not r["success"]]
    if failures:
        by_stage: dict[str, list[str]] = {}
        for r in failures:
            key = _classify_failure(r)
            by_stage.setdefault(key, []).append(r["name"])
        for key, names in sorted(by_stage.items(), key=lambda x: -len(x[1])):
            lines.append(f"- **{key}** ({len(names)}) : {', '.join(names)}")
    else:
        lines.append("_Aucun échec._")
    lines.append("")
    out_md = Path("docs/maintenance/failed-sources-dataset.md")
    out_md.write_text("\n".join(lines), encoding="utf-8")
    print(f"Markdown written → {out_md}")


def _classify_failure(r: dict) -> str:
    err = r["error"].lower()
    stages = r["stages"].lower()
    if "timeout" in err:
        return "Timeout 30s"
    if "blocked automated access" in err or "curl_cffi=failed" in stages:
        return "Anti-bot bloque httpx+curl-cffi"
    if "could not access url" in err:
        return "Réseau/DNS/TLS"
    if "a_tag_scan=0_candidates" in stages and "link_alternate=none" in stages:
        return "Homepage sans <link rel=alternate> ni <a> feed-like"
    if "suffix_fallback=tried_" in stages:
        return "Homepage parsée mais aucun suffixe commun ne matche"
    return "Autre"


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
