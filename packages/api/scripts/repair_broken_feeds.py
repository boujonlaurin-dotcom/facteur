#!/usr/bin/env python3
"""Réparation des flux cassés des grands médias (Composant 3) — JAMAIS supprimer.

Pour chaque source de l'allowlist `BROKEN_FEED_ALLOWLIST` (grands médias actifs,
curated, 0 content — cf. cleanup_orphan_sources.py) :
  1. **Probe** le `feed_url` actuel (HTTP status + nb d'items, via diagnose_feeds).
  2. **Répare** si un `feed_url` de remplacement connu existe ET qu'il probe OK
     (KNOWN_FIXES — Mécaniques du Complot).
  3. **Désactive** (`is_active=false`, réversible) les flux non réparables retenus
     par le PO (`DEACTIVATE`, surface B) : follows + lignes **conservés**, pas de
     hard-delete. Idempotent (no-op si déjà inactif).
  4. **Diagnostique + signale** le reste (décision PO au cas par cas).

Remplace l'anti-pattern SQL Editor `fix_stale_rss_sources.sql`.

Usage :
    cd packages/api
    python3 scripts/repair_broken_feeds.py                 # dry-run (probe + rapport)
    python3 scripts/repair_broken_feeds.py --apply --allow-prod
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from datetime import UTC, datetime
from pathlib import Path

import certifi
import httpx

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import text

from app.config import get_settings
from app.database import async_session_maker, engine
from scripts.cleanup_orphan_sources import BROKEN_FEED_ALLOWLIST, _is_test_db
from scripts.diagnose_feeds import test_feed

# Remplacements de feed_url connus (vieux feed_url -> nouveau). Seuls les flux
# dont on connaît une URL valide sont ici ; le reste est diagnostiqué + signalé.
# Mécaniques du Complot : radiofrance.fr/...rss (mort) -> radiofrance-podcast.net.
KNOWN_FIXES: dict[str, str] = {
    "https://www.radiofrance.fr/franceculture/podcasts/mecaniques-du-complot.rss": (
        "https://radiofrance-podcast.net/podcast09/rss_20682.xml"
    ),
}

# Flux cassés non réparables -> DÉSACTIVATION (is_active=false), décision PO
# verrouillée (surface B). Réversible : follows + lignes conservés, pas de delete.
# feed_url -> nom (le nom ne sert qu'au rapport ; l'UPDATE matche le feed_url).
DEACTIVATE: dict[str, str] = {
    "https://www.liberation.fr/rss/": "Libération",
    "https://www.alternatives-economiques.fr/flux-rss": "Alternatives Économiques",
    "https://services.lesechos.fr/rss/les-echos-une.xml": "Les Échos",
    "https://feeds.megaphone.fm/WWS2399238883": "Guerres de Business",
    "https://www.brut.media/fr/flux-rss": "Brut",
    "https://feeds.360.audion.fm/EZqjvOzZXgWIKWg0EETBQ": "Transfert",
}

_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36"
    )
}


async def _fetch_allowlist_sources(session) -> list[dict]:
    result = await session.execute(
        text(
            "SELECT id, name, type, feed_url, is_active, "
            "(SELECT count(*) FROM contents c WHERE c.source_id = sources.id) AS n_content, "
            "(SELECT count(*) FROM user_sources us WHERE us.source_id = sources.id) AS n_follow "
            "FROM sources WHERE feed_url = ANY(:feeds)"
        ),
        {"feeds": list(BROKEN_FEED_ALLOWLIST)},
    )
    return [dict(m) for m in result.mappings()]


async def diagnose(session, client: httpx.AsyncClient) -> list[dict]:
    """Probe chaque source allowlist + propose une réparation si connue."""
    sources = await _fetch_allowlist_sources(session)
    report: list[dict] = []
    for s in sources:
        current = await test_feed(client, s["name"], s["feed_url"])
        entry = {
            "name": s["name"],
            "id": str(s["id"]),
            "feed_url": s["feed_url"],
            "n_follow": s["n_follow"],
            "is_active": s["is_active"],
            "current_probe": {
                "http_status": current["http_status"],
                "entries": current["entries_count"],
                "status": current["status"],
                "error": current["error"],
            },
            "action": "diagnose_only",
            "new_feed_url": None,
        }
        new_url = KNOWN_FIXES.get(s["feed_url"])
        if new_url and new_url != s["feed_url"]:
            probe_new = await test_feed(client, s["name"], new_url)
            entry["new_feed_url"] = new_url
            entry["new_probe"] = {
                "http_status": probe_new["http_status"],
                "entries": probe_new["entries_count"],
                "status": probe_new["status"],
            }
            if probe_new["entries_count"] > 0:
                entry["action"] = "repair"
            else:
                entry["action"] = "fix_known_but_new_url_also_broken"
        elif s["feed_url"] in DEACTIVATE:
            # Désactivation PO (surface B). Idempotent : no-op si déjà inactif.
            entry["action"] = "deactivate" if s["is_active"] else "already_inactive"
        report.append(entry)
    return report


async def apply_repairs(session, report: list[dict]) -> dict:
    counts = {"repaired": 0, "deactivated": 0}
    for entry in report:
        if entry["action"] == "repair":
            await session.execute(
                text("UPDATE sources SET feed_url = :new WHERE id = :id"),
                {"new": entry["new_feed_url"], "id": entry["id"]},
            )
            counts["repaired"] += 1
        elif entry["action"] == "deactivate":
            await session.execute(
                text("UPDATE sources SET is_active = false WHERE id = :id"),
                {"id": entry["id"]},
            )
            counts["deactivated"] += 1
    return counts


def render_report(report: list[dict]) -> str:
    lines = ["=" * 78, "RÉPARATION FLUX CASSÉS — grands médias (allowlist)", "=" * 78]
    for e in report:
        cp = e["current_probe"]
        lines.append(
            f"• {e['name']} ({e['n_follow']} follows)  [{e['action'].upper()}]"
        )
        lines.append(
            f"    actuel : {e['feed_url']}\n"
            f"             HTTP {cp['http_status']} / {cp['entries']} items / {cp['status']}"
            + (f" / {cp['error']}" if cp["error"] else "")
        )
        if e["new_feed_url"]:
            np = e.get("new_probe", {})
            lines.append(
                f"    proposé: {e['new_feed_url']}\n"
                f"             HTTP {np.get('http_status')} / {np.get('entries')} items"
            )
        if e["action"] in ("deactivate", "already_inactive"):
            lines.append(
                "    -> is_active=false (réversible, follows conservés)"
                + (" [déjà inactif]" if e["action"] == "already_inactive" else "")
            )
    repairs = sum(1 for e in report if e["action"] == "repair")
    deacts = sum(1 for e in report if e["action"] == "deactivate")
    lines.append("-" * 78)
    lines.append(f"À réparer (URL connue + probe OK) : {repairs} / {len(report)}")
    lines.append(f"À désactiver (PO, réversible)     : {deacts} / {len(report)}")
    lines.append("Le reste : diagnostic seulement (décision PO).")
    lines.append("=" * 78)
    return "\n".join(lines)


def _backup_path() -> Path:
    ts = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    return (
        Path(__file__).resolve().parents[3]
        / ".context"
        / f"repair_feeds_report_{ts}.json"
    )


async def run(apply: bool, allow_prod: bool) -> int:
    settings = get_settings()
    db_url = settings.database_url or ""
    is_test = _is_test_db(db_url)
    print(
        f"DB cible : {db_url.split('@')[-1] if '@' in db_url else db_url}  (test={is_test})"
    )
    if apply and not is_test and not allow_prod:
        print("\nABORT : --apply contre une DB non-test sans --allow-prod (gated PO).")
        return 2

    async with (
        httpx.AsyncClient(
            timeout=30.0,
            follow_redirects=True,
            verify=certifi.where(),
            headers=_HEADERS,
        ) as client,
        async_session_maker() as session,
    ):
        try:
            report = await diagnose(session, client)
            bpath = _backup_path()
            bpath.parent.mkdir(parents=True, exist_ok=True)
            bpath.write_text(json.dumps(report, indent=2, ensure_ascii=False))
            print(f"Rapport écrit : {bpath}")
            print(render_report(report))

            if not apply:
                print("\n(dry-run — aucune mutation. Relance avec --apply.)")
                return 0

            counts = await apply_repairs(session, report)
            await session.commit()
            print(
                f"\nAPPLIQUÉ : {counts['repaired']} feed_url réparé(s), "
                f"{counts['deactivated']} source(s) désactivée(s)."
            )
            return 0
        except Exception:
            await session.rollback()
            raise
        finally:
            await engine.dispose()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--apply", action="store_true", help="exécute (défaut: dry-run)"
    )
    parser.add_argument(
        "--allow-prod", action="store_true", help="autorise --apply en prod (gated PO)"
    )
    args = parser.parse_args()
    sys.exit(asyncio.run(run(apply=args.apply, allow_prod=args.allow_prod)))


if __name__ == "__main__":
    main()
