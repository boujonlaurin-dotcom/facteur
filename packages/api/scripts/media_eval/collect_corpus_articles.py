#!/usr/bin/env python3
"""Collecteur voie A — échantillon d'articles (§5.4, corpus des critères C2–C7).

Instrumente le **corpus d'articles** qui fonde les critères sur échantillon
(C2 sourçage, C3 correction, C4 info/opinion, C5 diversité, C7 auteurs) : il
découvre des articles récents (home + sitemaps), snapshote leur texte dans
``media_eval_corpus_articles`` et calcule des **pré-métriques mécaniques** (une
signature est-elle présente ? un label d'opinion ? combien de liens sortants ?).

La *qualification* (taux de sources nommées, pluralité des perspectives, ton…)
reste voie B : l'agent ``media-eval-collecteur-corpus`` lit ce corpus exporté et
produit les signaux ``articles`` agrégés par critère. Ce collecteur ne pose
donc **aucun signal** — il alimente seulement la table corpus, que
``build_eval_input`` joint ensuite en contexte des eval_inputs C2/C3/C4/C5/C7.

Fenêtre : la fraîcheur des articles suit ``date_reference`` du run. Idempotent :
un article déjà présent (même url, même run) n'est pas ré-inséré. Ne lève jamais
sur un fetch bloqué (l'article est simplement ignoré, journalisé).

Usage :
    cd packages/api
    python3 scripts/media_eval/collect_corpus_articles.py --media cnews.fr \
        --run-id pilote-2026-08 [--max-articles 40] [--apply --allow-prod]
"""

from __future__ import annotations

import argparse
import asyncio
import re
import sys
from datetime import date
from functools import partial
from pathlib import Path
from urllib.parse import urljoin, urlparse

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from bs4 import BeautifulSoup
from sqlalchemy import select

from app.models.media_eval import MediaEvalCorpusArticle
from scripts.media_eval.collect_common import (
    CollectStats,
    Fetcher,
    _run,
    meme_domaine,
)
from scripts.media_eval.collect_pages_types import (
    _RE_HREF_ARTICLE,
    _base_url,
    extraire_texte_principal,
    parse_sitemap,
)

DEFAULT_MAX_ARTICLES = 40  # plafond §5.4 (20-40 articles informatifs)
_CORPUS_EXTRAIT_MAX = 20000  # même plafond que les snapshots de pages types

# Année dans l'URL → date approximative (sert de repli au <time datetime>).
# Séparateurs / ou - (CNEWS : /2026-07-18/…).
_RE_ANNEE_URL = re.compile(r"/((?:19|20)\d{2})[-/](\d{2})[-/](\d{2})")
_RE_ANNEE_SEULE = re.compile(r"/((?:19|20)\d{2})/")

# Rubriques hors périmètre « article » (pages de service, flux, tags).
_SEGMENTS_NON_ARTICLE = frozenset(
    {
        "tag", "tags", "auteur", "auteurs", "recherche", "search", "video",
        "videos", "podcast", "podcasts", "newsletter", "newsletters", "page",
        "rubrique", "mentions-legales", "cgu", "cgv", "contact", "abonnement",
        "boutique", "meteo", "programme", "programmes", "direct",
    }
)

# Labels d'opinion (URL / titre / classe) — indice mécanique, pas un verdict.
_LABELS_OPINION: tuple[str, ...] = (
    "tribune",
    "edito",
    "editorial",
    "éditorial",
    "chronique",
    "opinion",
    "point-de-vue",
    "point de vue",
    "billet",
    "humeur",
)
# Signatures non nominatives (recours à la rédaction / reprise d'agence).
_MARQUEURS_REDACTION: tuple[str, ...] = (
    "la rédaction",
    "la redaction",
    "rédaction de",
    "avec afp",
    "avec reuters",
    "source afp",
    "(afp)",
    "reuters",
)


# --------------------------------------------------------------------------- #
# Fonctions pures (str → structures) — testées sur fixtures, zéro réseau.
# --------------------------------------------------------------------------- #
def _segment_1(url: str) -> str | None:
    """Premier segment de chemin non vide d'une URL (proxy de rubrique)."""
    for seg in urlparse(url).path.split("/"):
        if seg:
            return seg.lower()
    return None


def est_url_article(url: str) -> bool:
    """True si l'URL ressemble à un article daté (et pas une page de service)."""
    if not _RE_HREF_ARTICLE.search(url.lower()):
        return False
    seg = _segment_1(url)
    return seg is None or seg not in _SEGMENTS_NON_ARTICLE


def rubrique_depuis_url(url: str) -> str | None:
    """Rubrique déduite du 1er segment de chemin (hors segment = année)."""
    seg = _segment_1(url)
    if seg is None or re.fullmatch(r"(?:19|20)\d{2}", seg):
        # /2026/... → prendre le segment suivant s'il est parlant.
        parts = [p for p in urlparse(url).path.split("/") if p]
        for p in parts:
            if not re.fullmatch(r"(?:19|20)\d{2}|\d{1,2}", p):
                return p.lower()[:100]
        return None
    return seg[:100]


def date_depuis_url(url: str) -> date | None:
    """Date approximative lue dans l'URL (/AAAA/MM/JJ ou /AAAA/)."""
    m = _RE_ANNEE_URL.search(url)
    if m:
        try:
            return date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
        except ValueError:
            return None
    m = _RE_ANNEE_SEULE.search(url)
    if m:
        return date(int(m.group(1)), 1, 1)
    return None


def extraire_urls_articles(
    base: str, home_html: str, sitemap_urls: list[str]
) -> list[str]:
    """URLs d'articles candidates (liens de la home + sitemap), dédupées.

    Ordre stable : liens de la home d'abord (les plus récents en pratique),
    puis sitemap. Les URLs hors périmètre article (pages de service) et hors
    domaine (``www.`` toléré) sont écartées.
    """
    ordonnes: list[str] = []
    vus: set[str] = set()
    netloc_base = urlparse(base).netloc
    soup = BeautifulSoup(home_html, "html.parser")
    liens_home = [
        a["href"].strip()
        for a in soup.find_all("a", href=True)
        if a["href"].strip() and not a["href"].startswith(("#", "mailto:", "javascript:"))
    ]
    for href in [*liens_home, *sitemap_urls]:
        url = urljoin(base + "/", href)  # no-op sur les URLs absolues du sitemap
        if not meme_domaine(urlparse(url).netloc, netloc_base):
            continue
        if est_url_article(url) and url not in vus:
            vus.add(url)
            ordonnes.append(url)
    return ordonnes


def extraire_titre(html: str) -> str | None:
    soup = BeautifulSoup(html, "html.parser")
    h1 = soup.find("h1")
    if h1 and h1.get_text(strip=True):
        return h1.get_text(" ", strip=True)[:300]
    if soup.title and soup.title.get_text(strip=True):
        return soup.title.get_text(" ", strip=True)[:300]
    return None


def date_depuis_html(html: str) -> date | None:
    """Date de publication depuis <time datetime> ou meta article:published_time."""
    soup = BeautifulSoup(html, "html.parser")
    meta = soup.find("meta", attrs={"property": "article:published_time"})
    brut = meta.get("content") if meta and meta.get("content") else None
    if brut is None:
        t = soup.find("time")
        brut = t.get("datetime") if t and t.get("datetime") else None
    if not brut:
        return None
    try:
        return date.fromisoformat(str(brut)[:10])
    except ValueError:
        return None


def _a_signature(html: str) -> bool:
    """Marqueur mécanique de signature (meta author / rel=author / classe auteur)."""
    soup = BeautifulSoup(html, "html.parser")
    meta = soup.find("meta", attrs={"name": "author"})
    if meta and (meta.get("content") or "").strip():
        return True
    if soup.find(attrs={"rel": "author"}) or soup.find(attrs={"itemprop": "author"}):
        return True
    for attr in ("class", "id"):
        if soup.find(attrs={attr: re.compile(r"(author|auteur|signature|byline)", re.I)}):
            return True
    return False


def _liens_sortants(url: str, html: str) -> int:
    """Nombre de liens du corps principal pointant vers un autre domaine."""
    soup = BeautifulSoup(html, "html.parser")
    for tag in soup(["header", "footer", "nav"]):
        tag.decompose()
    cible = soup.find("main") or soup.find("article") or soup.body or soup
    hrefs = [a.get("href", "") for a in cible.find_all("a", href=True)] if cible else []
    netloc_article = urlparse(url).netloc
    return sum(
        1
        for h in hrefs
        if h.startswith(("http://", "https://"))
        and not meme_domaine(urlparse(h).netloc, netloc_article)
    )


def pre_metriques_article(
    url: str, html: str, texte: str, titre: str | None = None
) -> dict:
    """Pré-métriques mécaniques (indices) — la qualification reste voie B."""
    cible = f"{url} {titre or extraire_titre(html) or ''} {texte[:600]}".lower()
    label = next((lab for lab in _LABELS_OPINION if lab in cible), None)
    return {
        "a_signature_html": _a_signature(html),
        "mention_redaction_ou_agence": any(m in texte.lower() for m in _MARQUEURS_REDACTION),
        "label_opinion": label,
        "liens_sortants": _liens_sortants(url, html),
        "longueur_texte": len(texte),
    }


# --------------------------------------------------------------------------- #
# Collecte.
# --------------------------------------------------------------------------- #
async def collecter_corpus(
    session,
    media,
    run,
    fetcher: Fetcher,
    *,
    max_articles: int = DEFAULT_MAX_ARTICLES,
) -> CollectStats:
    """Découvre et snapshote un échantillon d'articles (voie A, §5.4).

    ``inseres`` compte les articles snapshotés (pas des signaux) ; les fetchs
    bloqués ou vides sont journalisés en fin de ``details``.
    """
    stats = CollectStats()
    base = _base_url(media.domaine)

    home = await fetcher(base + "/")
    if home.bloque:
        stats.details.append("home inaccessible (anti-bot) — corpus vide")
        return stats

    sitemap = await fetcher(base + "/sitemap.xml")
    sitemap_urls = parse_sitemap(sitemap.text) if sitemap.ok else []
    candidats = extraire_urls_articles(base, home.text, sitemap_urls)

    # Idempotence : ne pas ré-insérer un article déjà présent pour (media, run).
    rows = await session.execute(
        select(MediaEvalCorpusArticle.url).where(
            MediaEvalCorpusArticle.media_id == media.id,
            MediaEvalCorpusArticle.run_id == run.run_id,
        )
    )
    deja = {r[0] for r in rows}

    ignores = 0
    for url in candidats:
        if stats.inseres >= max_articles:
            break
        if url in deja:
            stats.doublons += 1
            continue
        res = await fetcher(url)
        if not res.ok:
            ignores += 1
            continue
        texte = extraire_texte_principal(res.text)
        if len(texte) < 200:
            ignores += 1  # coquille / mur / page vide
            continue
        deja.add(url)
        titre = extraire_titre(res.text)
        session.add(
            MediaEvalCorpusArticle(
                media_id=media.id,
                run_id=run.run_id,
                url=url,
                titre=titre,
                date_pub=date_depuis_html(res.text) or date_depuis_url(url),
                rubrique=rubrique_depuis_url(url),
                texte=texte[:_CORPUS_EXTRAIT_MAX],
                mode_acquisition="http",
                pre_metriques=pre_metriques_article(url, res.text, texte, titre),
            )
        )
        stats.inseres += 1
        stats.details.append(f"{url} ({rubrique_depuis_url(url) or 'rubrique?'})")
    if ignores:
        stats.details.append(f"ignorés (bloqué/vide) : {ignores}")
    return stats


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--media", required=True, help="domaine (ex. cnews.fr)")
    parser.add_argument("--run-id", required=True, help="ex. pilote-2026-08")
    parser.add_argument(
        "--max-articles",
        type=int,
        default=DEFAULT_MAX_ARTICLES,
        help=f"plafond d'articles échantillonnés (défaut {DEFAULT_MAX_ARTICLES}, §5.4)",
    )
    parser.add_argument(
        "--apply", action="store_true", help="exécute (défaut: dry-run)"
    )
    parser.add_argument(
        "--allow-prod", action="store_true", help="autorise --apply en prod"
    )
    args = parser.parse_args()
    # Harnais commun (garde --apply/--allow-prod, dry-run, rollback) : seul le
    # plafond d'articles est spécifique à ce collecteur.
    sys.exit(
        asyncio.run(
            _run(
                "corpus",
                partial(collecter_corpus, max_articles=args.max_articles),
                media_domaine=args.media,
                run_id=args.run_id,
                apply=args.apply,
                allow_prod=args.allow_prod,
                libelle="articles",
            )
        )
    )


if __name__ == "__main__":
    main()
