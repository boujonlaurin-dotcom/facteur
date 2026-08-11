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

### Deux modes, deux registres

Par défaut le collecteur découvre les articles dans le **flux du jour**. La
fenêtre d'un flux tourne en quelques jours, et `html/` n'est pas versionné :
un clone neuf hérite donc d'un `labels.json` sans charges utiles, qu'une
recollecte ne rend pas — elle ramène les articles du jour, non étiquetés.
`--refetch-from-labels` part de `labels.json` au lieu du flux et re-fetch le
HTML par URL, ce qui rend un étiquetage ancien à nouveau mesurable.

Usage :
    cd packages/api
    PYTHONPATH=. python scripts/build_paywall_corpus.py --check
    PYTHONPATH=. python scripts/build_paywall_corpus.py
    PYTHONPATH=. python scripts/build_paywall_corpus.py --source novethic
    PYTHONPATH=. python scripts/build_paywall_corpus.py --refresh-html
    PYTHONPATH=. python scripts/build_paywall_corpus.py --refetch-from-labels

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


async def refetch_from_labels(
    client: httpx.AsyncClient,
    labels: dict[str, dict],
    slugs: set[str] | None,
    *,
    refresh_html: bool,
) -> list[dict[str, Any]]:
    """Re-fetch le HTML des articles déjà au corpus, par URL, sans passer par le flux.

    La collecte normale découvre les articles dans le flux **du jour**, et la
    fenêtre d'un flux tourne vite : mesuré le 2026-08-11, 14 des 30 URL
    étiquetées 3 jours plus tôt y figuraient encore, et **aucune** des 15 URL de
    quotidiens. Comme `html/` n'est pas versionné alors que `labels.json` l'est,
    un clone neuf hérite d'un étiquetage sans charges utiles — qu'aucune
    recollecte ne rend, puisqu'elle ramène les articles du jour, non étiquetés.
    L'étiquetage humain, seul travail non automatisable du chantier, se
    dévaluait donc tout seul.

    Ce mode part de `labels.json`, qui est le vrai registre du corpus : le flux
    n'est que la façon dont les articles y sont entrés. Il ne touche ni aux
    labels (il n'y a rien de nouveau à découvrir) ni au rapport de collecte (qui
    décrit une collecte par flux, pas celle-ci).

    Limite assumée : le RSS d'un article sorti du flux est perdu sans recours,
    donc le harnais rejouera ces cas avec un titre et une description vides.
    C'est sans effet tant que le niveau 2 est inerte — aucun mot-clé de
    `DEFAULT_PAYWALL_CONFIG` n'apparaît dans les 301 entrées RSS collectées —
    mais ça invaliderait une mesure qui porterait sur le niveau 2.
    """
    par_source: dict[str, dict[str, Any]] = {}
    for aid, row in sorted(labels.items()):
        slug = row["source"]
        if slugs is not None and slug not in slugs:
            continue

        stats = par_source.setdefault(
            slug, {"slug": slug, "ok": 0, "cached": 0, "failed": 0, "failures": []}
        )
        html_path = HTML_DIR / f"{aid}.html"
        if html_path.exists() and not refresh_html:
            stats["cached"] += 1
            continue

        html, status = await fetch_html_head(client, row["url"])
        if html is None:
            stats["failed"] += 1
            stats["failures"].append({"url": row["url"], "status": status})
            continue

        HTML_DIR.mkdir(parents=True, exist_ok=True)
        html_path.write_text(html, encoding="utf-8")
        stats["ok"] += 1

    return [par_source[slug] for slug in sorted(par_source)]


def _now() -> str:
    return datetime.datetime.now(datetime.UTC).isoformat()


def quota_status(manifest: dict, labels: dict[str, dict]) -> dict[str, dict]:
    """État d'étiquetage par source : comptes, complétude, respect du quota.

    Source unique de la règle de quota, partagée avec
    `tests/test_paywall_corpus_benchmark.py` — le collecteur en fait un
    avertissement, le test un verdict, mais tous deux comptent pareil.

    Trois cas que le comptage brut traitait à tort comme des manquements :

    - **Source sans article collecté** (`lesechos`, `lepoint` : 403 anti-bot).
      Elle est au manifeste mais hors corpus ; il n'y a rien à étiqueter, donc
      rien à reprocher. Elle est absente du résultat.
    - **Étiquetage en cours.** Tant qu'il reste des `label: null`, le quota
      n'est pas « non tenu », il est *pas encore* tenu. `complete` distingue
      les deux, et seul un étiquetage terminé peut constituer un défaut — c'est
      alors le corpus qu'il faut élargir, pas l'étiquetage qu'il faut attendre.
    - **Média entièrement gratuit** (`expects_paid: false` au manifeste).
      Exiger 3 articles payants de Contrepoints ou Bon Pote reviendrait à
      demander ce que le média ne publie pas. Le quota de gratuits, lui,
      s'applique toujours : c'est la seule mesure des faux positifs, et ces
      sources sont précisément le piège qui les révèle.
    """
    min_paid = manifest.get("min_paid_per_source", 3)
    min_free = manifest.get("min_free_per_source", 3)

    status: dict[str, dict] = {}
    for source in manifest["sources"]:
        slug = source["slug"]
        rows = [row for row in labels.values() if row["source"] == slug]
        if not rows:
            continue

        paid = sum(1 for row in rows if row["label"] == "paid")
        free = sum(1 for row in rows if row["label"] == "free")
        unlabeled = sum(1 for row in rows if row["label"] is None)
        expects_paid = source.get("expects_paid", True)
        status[slug] = {
            "paid": paid,
            "free": free,
            "unlabeled": unlabeled,
            "expects_paid": expects_paid,
            "complete": unlabeled == 0,
            "meets_quota": free >= min_free and (paid >= min_paid or not expects_paid),
        }
    return status


def summarize_quota(manifest: dict, labels: dict[str, dict]) -> list[str]:
    """Signale les sources qui ne tiennent pas le quota 3 payants / 3 gratuits."""
    min_paid = manifest.get("min_paid_per_source", 3)
    min_free = manifest.get("min_free_per_source", 3)
    warnings = []
    for slug, state in quota_status(manifest, labels).items():
        if state["meets_quota"]:
            continue
        attendu = f"{min_paid}/{min_free}" if state["expects_paid"] else f"–/{min_free}"
        reste = (
            "étiquetage terminé"
            if state["complete"]
            else f"{state['unlabeled']} à étiqueter"
        )
        warnings.append(
            f"  {slug:<16} {state['paid']} payants / {state['free']} gratuits "
            f"({reste}) — quota {attendu} non tenu"
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

        if args.refetch_from_labels:
            if not labels:
                print(
                    "labels.json est vide : rien à re-fetcher. Lance d'abord une "
                    "collecte par flux.",
                    file=sys.stderr,
                )
                return 2
            return _report_refetch(
                await refetch_from_labels(
                    client,
                    labels,
                    {s["slug"] for s in sources} if args.source else None,
                    refresh_html=args.refresh_html,
                )
            )

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


def _report_refetch(stats: list[dict[str, Any]]) -> int:
    """Affiche le résultat du re-fetch. Un HTML manquant n'est pas un échec.

    Les 403 anti-bot et les redirections en boucle font partie du terrain : le
    corpus vit avec des sources dont le HTML est inatteignable, et le harnais
    les mesure au niveau 2. Le code de retour ne signale donc que l'absence
    totale de récupération, qui elle trahit un problème d'egress.
    """
    print(f"{'source':<16}{'récupérés':>10}{'en cache':>10}{'échecs':>8}")
    for row in stats:
        print(f"{row['slug']:<16}{row['ok']:>10}{row['cached']:>10}{row['failed']:>8}")

    echecs = [(row["slug"], f) for row in stats for f in row["failures"]]
    if echecs:
        print("\nHTML inatteignable (attendu sur les sources anti-bot) :")
        for slug, failure in echecs:
            # Un motif d'échec peut dépasser la colonne (TooManyRedirects et sa
            # phrase) : le séparateur explicite évite qu'il colle à l'URL.
            print(f"  {slug:<16}{failure['status']:<24}  {failure['url']}")

    total_ok = sum(row["ok"] for row in stats)
    total_cache = sum(row["cached"] for row in stats)
    print(f"\n{total_ok} HTML récupérés, {total_cache} déjà en cache.")
    if total_ok == 0 and total_cache == 0:
        print(
            "Aucun HTML récupéré : vérifie l'egress avec --check.",
            file=sys.stderr,
        )
        return 1
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
        "--refetch-from-labels",
        action="store_true",
        help=(
            "re-fetch le HTML des articles déjà au corpus par URL, sans passer "
            "par le flux (récupère un étiquetage dont les charges utiles ont "
            "été perdues au clone)"
        ),
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="teste seulement l'accès réseau aux flux, n'écrit rien",
    )
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
