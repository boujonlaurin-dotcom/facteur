"""Collecte le **corpus de vérité terrain** de la détection paywall.

Ce script produit les fixtures que `tests/test_paywall_corpus_benchmark.py`
rejoue. Il ne juge rien : il capture, à l'identique de la production, les deux
surfaces que `detect_paywall()` voit, et laisse le label humain à `labels.json`.

### Pourquoi deux surfaces distinctes

`process_source` lit le flux RSS **et** fetch les 50 premiers Ko de la page.
`seed_recent_content` ne lit que le RSS (`html_head=None` explicite, l.249 de
`sync_service.py`). Un marqueur de paywall présent sur la page web peut être
totalement absent du flux, et l'inverse arrive aussi. Le corpus stocke donc les
deux séparément, pour pouvoir mesurer chaque niveau isolément.

### Fidélité à la production — non négociable

Le fetch réplique `SyncService._fetch_html_head` **et** le client qui le porte
(`sync_service.py` l.32-40) : même User-Agent Chrome, `follow_redirects=True`,
bundle certifi, en-tête `Range: bytes=0-50000`, timeout 5 s, acceptation des
codes 200 **et** 206, troncature à 50 000 caractères. Toute divergence ici
rendrait la baseline non représentative : c'est le seul endroit du corpus où
une approximation se paie en mesure fausse.

Le fetch du flux réplique `_fetch_feed_content`, repli anti-bot compris.

### Append-only sur les labels

`labels.json` est la propriété de l'humain qui étiquette. Le script y **ajoute**
les articles nouvellement découverts avec `label: null`, et ne réécrit jamais un
label existant. Un label ne se déduit pas de l'algo — sinon la mesure valide
l'algo par lui-même.

Usage :
    cd packages/api
    PYTHONPATH=. python scripts/build_paywall_corpus.py --check
    PYTHONPATH=. python scripts/build_paywall_corpus.py
    PYTHONPATH=. python scripts/build_paywall_corpus.py --source novethic
    PYTHONPATH=. python scripts/build_paywall_corpus.py --refresh-html

Sorties (toutes sous tests/fixtures/paywall_corpus/) :
    rss/<slug>.json            entrées de flux brutes, telles que feedparser les voit
    html/<article_id>.html     50 premiers Ko de la page, tels que la prod les fetch
    labels.json                vérité terrain, saisie à la main
    collection_report.json     ce qui a marché, ce qui a échoué, quand
"""

from __future__ import annotations

import argparse
import asyncio
import datetime
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

import certifi
import feedparser
import httpx
import yaml

CORPUS_DIR = Path(__file__).resolve().parent.parent / "tests/fixtures/paywall_corpus"
MANIFEST_PATH = CORPUS_DIR / "manifest.yaml"
LABELS_PATH = CORPUS_DIR / "labels.json"
REPORT_PATH = CORPUS_DIR / "collection_report.json"
RSS_DIR = CORPUS_DIR / "rss"
HTML_DIR = CORPUS_DIR / "html"

# Réplique exacte de SyncService.__init__ (sync_service.py l.32-40).
PROD_USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)
HTML_HEAD_RANGE = "bytes=0-50000"
HTML_HEAD_TIMEOUT = 5.0
HTML_HEAD_MAX_CHARS = 50000


def article_id(slug: str, url: str) -> str:
    """Identifiant stable et lisible d'un article du corpus."""
    return f"{slug}-{hashlib.sha1(url.encode()).hexdigest()[:10]}"


def load_manifest() -> dict[str, Any]:
    return yaml.safe_load(MANIFEST_PATH.read_text(encoding="utf-8"))


def load_labels() -> dict[str, dict]:
    if not LABELS_PATH.exists():
        return {}
    return json.loads(LABELS_PATH.read_text(encoding="utf-8"))


def entry_to_record(entry: Any) -> dict[str, Any]:
    """Extrait d'une entrée feedparser exactement ce que `_parse_entry` lit.

    On garde `content` (le `content:encoded`) en plus des champs utilisés
    aujourd'hui : c'est la surface RSS complète, et une piste d'amélioration
    peut vouloir y chercher un marqueur que le code actuel ignore.
    """
    content_blocks = entry.get("content") or []
    return {
        "title": entry.get("title"),
        "link": entry.get("link"),
        "id": entry.get("id"),
        "summary": entry.get("summary"),
        "published": entry.get("published"),
        "updated": entry.get("updated"),
        "content": [
            {"type": block.get("type"), "value": block.get("value")}
            for block in content_blocks
        ],
        "tags": [tag.get("term") for tag in (entry.get("tags") or [])],
        "author": entry.get("author"),
    }


async def fetch_feed(
    client: httpx.AsyncClient, candidates: list[str]
) -> tuple[str | None, str | None, str | None]:
    """Essaie chaque URL candidate, retourne (url_retenue, corps, erreur)."""
    last_error = None
    for url in candidates:
        try:
            response = await client.get(url)
            response.raise_for_status()
            parsed = feedparser.parse(response.text)
            if parsed.entries:
                return url, response.text, None
            last_error = f"{url}: flux parsé mais 0 entrée"
        except Exception as exc:  # noqa: BLE001 — on veut la raison, pas le type
            last_error = f"{url}: {type(exc).__name__} {exc}"
    return None, None, last_error


async def fetch_html_head(
    client: httpx.AsyncClient, url: str
) -> tuple[str | None, str]:
    """Réplique `SyncService._fetch_html_head`, mais en rapportant l'échec.

    La prod avale l'erreur en silence (le scoring prend le relais) ; ici on veut
    savoir *pourquoi* un HTML manque, sinon un corpus troué passerait pour un
    corpus où le niveau 1 ne dit rien.
    """
    try:
        response = await client.get(
            url,
            headers={"Range": HTML_HEAD_RANGE},
            timeout=HTML_HEAD_TIMEOUT,
        )
        if response.status_code in (200, 206):
            return response.text[:HTML_HEAD_MAX_CHARS], f"ok {response.status_code}"
        return None, f"http {response.status_code}"
    except Exception as exc:  # noqa: BLE001
        return None, f"{type(exc).__name__}: {exc}"


async def collect_source(
    client: httpx.AsyncClient,
    source: dict[str, Any],
    labels: dict[str, dict],
    *,
    max_articles: int,
    refresh_html: bool,
) -> dict[str, Any]:
    slug = source["slug"]
    report: dict[str, Any] = {
        "slug": slug,
        "name": source["name"],
        "group": source["group"],
        "feed_url": None,
        "feed_error": None,
        "articles": [],
    }

    feed_url, body, error = await fetch_feed(client, source.get("feed_candidates", []))
    report["feed_url"] = feed_url
    report["feed_error"] = error

    urls: list[str] = list(source.get("seed_urls") or [])
    entries_by_url: dict[str, dict] = {}

    if body is not None:
        parsed = feedparser.parse(body)
        records = [entry_to_record(entry) for entry in parsed.entries[:50]]
        RSS_DIR.mkdir(parents=True, exist_ok=True)
        (RSS_DIR / f"{slug}.json").write_text(
            json.dumps(
                {"feed_url": feed_url, "fetched_at": _now(), "entries": records},
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
        for record in records:
            if record["link"]:
                entries_by_url[record["link"]] = record
        for record in records:
            if record["link"] and record["link"] not in urls:
                urls.append(record["link"])

    HTML_DIR.mkdir(parents=True, exist_ok=True)
    for url in urls[:max_articles]:
        aid = article_id(slug, url)
        html_path = HTML_DIR / f"{aid}.html"
        if html_path.exists() and not refresh_html:
            status = "cached"
        else:
            html, status = await fetch_html_head(client, url)
            if html is not None:
                html_path.write_text(html, encoding="utf-8")

        report["articles"].append({"id": aid, "url": url, "html_status": status})

        # Append-only : on n'écrase jamais un label déjà posé.
        if aid not in labels:
            labels[aid] = {
                "source": slug,
                "url": url,
                "label": None,
                "label_method": "manual",
                "observed_signal": None,
                "in_rss": url in entries_by_url,
            }

    return report


def _now() -> str:
    return datetime.datetime.now(datetime.UTC).isoformat()


def summarize_quota(manifest: dict, labels: dict[str, dict]) -> list[str]:
    """Signale les sources qui ne tiennent pas le quota 3 payants / 3 gratuits."""
    warnings = []
    min_paid = manifest.get("min_paid_per_source", 3)
    min_free = manifest.get("min_free_per_source", 3)
    for source in manifest["sources"]:
        slug = source["slug"]
        rows = [row for row in labels.values() if row["source"] == slug]
        paid = sum(1 for row in rows if row["label"] == "paid")
        free = sum(1 for row in rows if row["label"] == "free")
        unlabeled = sum(1 for row in rows if row["label"] is None)
        if paid < min_paid or free < min_free:
            warnings.append(
                f"  {slug:<16} {paid} payants / {free} gratuits "
                f"({unlabeled} à étiqueter) — quota {min_paid}/{min_free} non tenu"
            )
    return warnings


async def run(args: argparse.Namespace) -> int:
    manifest = load_manifest()
    labels = load_labels()
    sources = manifest["sources"]
    if args.source:
        sources = [s for s in sources if s["slug"] in args.source]
        if not sources:
            print(f"Aucune source ne correspond à {args.source}", file=sys.stderr)
            return 2

    max_articles = args.max_articles or manifest.get("max_articles_per_source", 10)

    async with httpx.AsyncClient(
        timeout=30.0,
        follow_redirects=True,
        verify=certifi.where(),
        headers={"User-Agent": PROD_USER_AGENT},
    ) as client:
        if args.check:
            return await run_check(client, sources)

        reports = []
        for source in sources:
            print(f"→ {source['name']}")
            report = await collect_source(
                client,
                source,
                labels,
                max_articles=max_articles,
                refresh_html=args.refresh_html,
            )
            if report["feed_error"] and not report["feed_url"]:
                print(f"  flux introuvable : {report['feed_error']}", file=sys.stderr)
            reports.append(report)

    LABELS_PATH.write_text(
        json.dumps(labels, ensure_ascii=False, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    REPORT_PATH.write_text(
        json.dumps(
            {"collected_at": _now(), "sources": reports}, ensure_ascii=False, indent=2
        ),
        encoding="utf-8",
    )

    print(f"\nLabels : {LABELS_PATH}")
    print(f"Rapport: {REPORT_PATH}")
    warnings = summarize_quota(manifest, labels)
    if warnings:
        print("\nQuota non tenu — le corpus n'est pas encore mesurable :")
        print("\n".join(warnings))
        print(
            "\nÉtiquette les articles à la main dans labels.json "
            '("paid" ou "free"), puis relance le harnais.'
        )
    return 0


async def run_check(client: httpx.AsyncClient, sources: list[dict]) -> int:
    """Teste l'accès réseau à chaque domaine sans rien écrire.

    À lancer en premier : si l'egress bloque les domaines de presse, la
    collecte produirait un corpus vide qu'on pourrait confondre avec « ces
    sources n'émettent aucun signal ».
    """
    blocked = []
    for source in sources:
        candidates = source.get("feed_candidates", [])
        url, _, error = await fetch_feed(client, candidates)
        if url:
            print(f"  OK      {source['slug']:<16} {url}")
        else:
            print(f"  BLOQUÉ  {source['slug']:<16} {error}")
            blocked.append(source["slug"])
    if blocked:
        print(f"\n{len(blocked)} source(s) inaccessibles : {', '.join(blocked)}")
        return 1
    print("\nToutes les sources sont accessibles.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source", action="append", help="slug à collecter (répétable)"
    )
    parser.add_argument("--max-articles", type=int, help="articles max par source")
    parser.add_argument(
        "--refresh-html",
        action="store_true",
        help="re-fetch les HTML déjà présents (par défaut ils sont conservés)",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="teste seulement l'accès réseau aux flux, n'écrit rien",
    )
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
