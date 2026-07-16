#!/usr/bin/env python3
"""Collecteur voie A — pages types du site (découverte + détection).

Découvre les pages institutionnelles (mentions légales, charte, ligne
éditoriale, régie pub, dons, à-propos/ours) par : liens du footer/home →
chemins types connus → sitemap. Émet des signaux de **détection** (présence
d'une page), la *substance* restant à la voie B :

- mentions légales → C5/``mentions_legales``
- charte → C8/``charte_deontologique`` (``valeur.detection="page_type"``)
- ligne éditoriale → C11/``ligne_editoriale_publiee``
- régie pub → C7/``regie_pub_identifiee``
- dons/financement → C5/``transparence_financement``
- à-propos / ours → **snapshot seul** (contexte, pas de signal)

Une page n'est retenue que si elle est **significative** (``page_significative``) :
statut 200, corps non vide, **≠ soft-404** (un site qui sert sa home sur un
chemin inexistant partage le hash du texte principal — écarté) et **portant les
marqueurs lexicaux** de son type (une page de flux taggé « /publicite » n'est
pas une page de régie). Épuisement des candidats sans page significative →
``absent_verifie`` avec ``sources_consultees`` complètes (preuve de recherche).
Fetch bloqué → ``bloque_acces`` (jamais d'exception). Idempotent (dédupe).

Usage :
    cd packages/api
    python3 scripts/media_eval/collect_pages_types.py --media reporterre.net \
        --run-id pilote-2026-07 [--apply --allow-prod]
"""

from __future__ import annotations

import hashlib
import re
import sys
from difflib import SequenceMatcher
from pathlib import Path
from urllib.parse import urljoin

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from bs4 import BeautifulSoup

from app.models.media_eval import TypePage
from scripts.media_eval.collect_common import (
    Collecteur,
    CollectStats,
    Fetcher,
    ouvrir_collecteur,
    run_cli,
)

COLLECTEUR = "code:collect_pages_types@v1"

# Chemins candidats par type de page — conventions FR + variantes SPIP
# (Reporterre est un site SPIP : `spip.php?page=…`, `spip.php?rubrique=…`).
CHEMINS_TYPES: dict[TypePage, tuple[str, ...]] = {
    TypePage.MENTIONS_LEGALES: (
        "/mentions-legales",
        "/mentions-legales.html",
        "/informations-legales",
        "/spip.php?page=mentions-legales",
    ),
    TypePage.A_PROPOS: (
        "/qui-sommes-nous",
        "/a-propos",
        "/about",
        "/qui-sommes-nous.html",
        "/spip.php?rubrique=qui-sommes-nous",
    ),
    TypePage.CHARTE: (
        "/charte",
        "/charte-deontologique",
        "/charte-ethique",
        "/deontologie",
        "/notre-charte",
        "/spip.php?page=charte",
    ),
    TypePage.OURS_EQUIPE: (
        "/ours",
        "/equipe",
        "/la-redaction",
        "/redaction",
        "/notre-equipe",
    ),
    TypePage.DONS_FINANCEMENT: (
        "/dons",
        "/nous-soutenir",
        "/soutenir",
        "/faire-un-don",
        "/don",
    ),
    TypePage.LIGNE_EDITORIALE: (
        "/ligne-editoriale",
        "/notre-ligne-editoriale",
        "/manifeste",
        "/notre-projet",
    ),
    TypePage.REGIE_PUB: (
        "/regie-publicitaire",
        "/publicite",
        "/annonceurs",
        "/regie",
    ),
}

# Type de page → (critère, type_signal). Absent ⇒ snapshot seul.
PAGE_SIGNAUX: dict[TypePage, tuple[str, str]] = {
    TypePage.MENTIONS_LEGALES: ("C5", "mentions_legales"),
    TypePage.CHARTE: ("C8", "charte_deontologique"),
    TypePage.LIGNE_EDITORIALE: ("C11", "ligne_editoriale_publiee"),
    TypePage.REGIE_PUB: ("C7", "regie_pub_identifiee"),
    TypePage.DONS_FINANCEMENT: ("C5", "transparence_financement"),
}
PAGES_SNAPSHOT_SEUL: frozenset[TypePage] = frozenset(
    {TypePage.A_PROPOS, TypePage.OURS_EQUIPE}
)

# Mots-clés de classification d'une URL/texte de lien vers un type de page.
_MOTS_CLES: tuple[tuple[TypePage, tuple[str, ...]], ...] = (
    (
        TypePage.MENTIONS_LEGALES,
        ("mentions-legales", "mentions legales", "informations-legales"),
    ),
    (TypePage.CHARTE, ("charte", "deontolog", "ethique", "ethiq")),
    (
        TypePage.LIGNE_EDITORIALE,
        ("ligne-editoriale", "ligne editoriale", "manifeste", "notre-projet"),
    ),
    (TypePage.REGIE_PUB, ("regie", "publicite", "annonceur", "publicitaire")),
    (
        TypePage.DONS_FINANCEMENT,
        ("faire-un-don", "nous-soutenir", "/dons", "/don", "soutenir", "financer"),
    ),
    (
        TypePage.OURS_EQUIPE,
        ("/ours", "la-redaction", "notre-equipe", "/equipe", "/redaction"),
    ),
    (TypePage.A_PROPOS, ("qui-sommes-nous", "a-propos", "/about")),
)

_MARQUEURS_404 = (
    "page introuvable",
    "page non trouvée",
    "page non trouvee",
    "erreur 404",
    "404 - ",
    "n'existe pas",
    "n existe pas",
    "cette page n",
    "introuvable",
)

# Marqueurs lexicaux exigés dans le corps AVANT d'émettre ``present`` : une page
# dont l'URL ressemble au type mais dont le texte ne porte aucun de ces mots
# n'est pas la page institutionnelle attendue (ex. un fil d'articles taggé
# « /publicite » n'est pas une page de régie). Substance, pas seulement l'URL.
_MARQUEURS_TYPE: dict[TypePage, tuple[str, ...]] = {
    TypePage.MENTIONS_LEGALES: (
        "mentions légales",
        "mentions legales",
        "éditeur",
        "editeur",
        "capital",
        "rcs",
        "siren",
        "siret",
        "issn",
        "directeur de la publication",
        "directeur de publication",
        "hébergeur",
    ),
    TypePage.CHARTE: (
        "charte",
        "déontolog",
        "deontolog",
        "éthique",
        "ethique",
        "code de conduite",
    ),
    TypePage.REGIE_PUB: (
        "régie",
        "annonceur",
        "tarif",
        "espace publicitaire",
        "kit média",
        "kit media",
        "contact commercial",
        "offres publicitaires",
    ),
    TypePage.DONS_FINANCEMENT: (
        "faire un don",
        "faites un don",
        "nous soutenir",
        "soutenez",
        "votre don",
        "adhérer",
        "adhésion",
        "financement participatif",
        "soutenir la rédaction",
        "faire un legs",
    ),
    TypePage.LIGNE_EDITORIALE: (
        "ligne éditoriale",
        "ligne editoriale",
        "manifeste",
        "notre projet",
        "notre mission",
        "projet éditorial",
        "notre engagement",
    ),
}

# Types dont une page authentique n'est PAS un fil d'articles datés : on écarte
# les pages de flux taggé (« /dons », « /publicite ») même si un marqueur y
# apparaît au fil des titres.
_TYPES_ANTI_FLUX: frozenset[TypePage] = frozenset(
    {TypePage.DONS_FINANCEMENT, TypePage.REGIE_PUB}
)

# Un href d'article daté : segment année (/2026/…, /2026-…) ou id numérique long.
_RE_HREF_ARTICLE = re.compile(r"/(?:19|20)\d{2}[-/]|[-/]\d{6,}(?:[/?#]|$)")

_LONGUEUR_HASH = 20000  # même plafond que le contenu snapshotté (Collecteur.snapshot)
_SIMILARITE_HOME = 0.9  # au-delà : page tenue pour identique à la home (soft-404)
_RATIO_FLUX_MAX = 0.5  # > 50 % de liens-articles dans le corps ⇒ page de flux


# --------------------------------------------------------------------------- #
# Fonctions pures (str → structures) — testées sur fixtures, zéro réseau.
# --------------------------------------------------------------------------- #
def parse_liens_footer(html: str) -> list[tuple[str, str]]:
    """Liens (href, texte) du footer/nav — source de découverte principale."""
    soup = BeautifulSoup(html, "html.parser")
    liens: list[tuple[str, str]] = []
    vus: set[str] = set()
    zones = soup.find_all(["footer", "nav"]) or [soup]
    for zone in zones:
        for a in zone.find_all("a", href=True):
            href = a["href"].strip()
            if not href or href.startswith(("#", "javascript:", "mailto:")):
                continue
            if href in vus:
                continue
            vus.add(href)
            liens.append((href, a.get_text(" ", strip=True)))
    return liens


def parse_sitemap(xml: str) -> list[str]:
    """URLs d'un sitemap (ou index de sitemaps) — balises <loc>."""
    soup = BeautifulSoup(xml, "xml")
    return [
        loc.get_text(strip=True)
        for loc in soup.find_all("loc")
        if loc.get_text(strip=True)
    ]


def classifier_url(url: str, texte: str = "") -> TypePage | None:
    """Type de page déduit d'une URL (+ texte de lien) — None si indéterminé."""
    cible = f"{url} {texte}".lower()
    for type_page, mots in _MOTS_CLES:
        if any(mot in cible for mot in mots):
            return type_page
    return None


def extraire_texte_principal(html: str) -> str:
    """Texte visible principal (hors nav/scripts) — pour la détection soft-404."""
    soup = BeautifulSoup(html, "html.parser")
    for tag in soup(["script", "style", "nav", "header", "footer", "noscript"]):
        tag.decompose()
    cible = soup.find("main") or soup.find("article") or soup.body or soup
    return cible.get_text(" ", strip=True)


def _hash_principal(texte: str) -> str:
    """sha256 du texte principal (plafonné comme le contenu snapshotté)."""
    return hashlib.sha256(texte[:_LONGUEUR_HASH].encode()).hexdigest()


def ressemble_a_home(texte: str, home_texte: str | None) -> bool:
    """True si le texte principal est identique (ou quasi) à celui de la home.

    Certains sites servent leur accueil sur des chemins inexistants (soft-404
    silencieux, HTTP 200) : ``/charte`` renvoie alors la home. Ces coquilles
    partagent le hash du texte principal de la home — on les refuse.
    """
    if not home_texte:
        return False
    if _hash_principal(texte) == _hash_principal(home_texte):
        return True
    ratio = SequenceMatcher(None, home_texte[:5000], texte[:5000]).ratio()
    return ratio > _SIMILARITE_HOME


def ratio_liens_articles(html: str) -> float:
    """Part des liens du contenu principal pointant vers un article daté.

    Une page institutionnelle (mentions, régie) renvoie peu de liens et pas
    vers un fil d'articles ; une page de flux taggé en renvoie beaucoup.
    """
    soup = BeautifulSoup(html, "html.parser")
    for tag in soup(["header", "footer", "nav"]):
        tag.decompose()
    cible = soup.find("main") or soup.find("article") or soup.body or soup
    liens = cible.find_all("a", href=True) if cible else []
    if not liens:
        return 0.0
    articles = sum(1 for a in liens if _RE_HREF_ARTICLE.search(a["href"].lower()))
    return articles / len(liens)


def a_marqueurs_type(texte: str, html: str, type_page: TypePage) -> bool:
    """Le corps porte-t-il les marqueurs lexicaux attendus pour ce type ?

    Types snapshot-seul (à-propos / ours) : aucune exigence. Types anti-flux
    (dons / régie) : marqueur requis ET pas un fil d'articles datés.
    """
    marqueurs = _MARQUEURS_TYPE.get(type_page)
    if marqueurs is None:
        return True
    bas = texte.lower()
    if not any(m in bas for m in marqueurs):
        return False
    return not (
        type_page in _TYPES_ANTI_FLUX and ratio_liens_articles(html) > _RATIO_FLUX_MAX
    )


def page_significative(
    html: str,
    status: int | None,
    *,
    type_page: TypePage | None = None,
    home_texte: str | None = None,
) -> bool:
    """True si la page existe vraiment ET porte la substance de son type.

    - ``status`` ≠ 200, coquille vide ou marqueur 404 → non significative ;
    - contenu identique (ou quasi) à la home → soft-404 silencieux, écartée ;
    - ``type_page`` fourni sans marqueur lexical attendu → écartée (une page de
      flux taggé « /dons », « /publicite » n'est pas une page institutionnelle).

    ``home_texte`` / ``type_page`` sont optionnels (rétrocompat) : sans eux, seul
    le socle existence (statut + longueur + marqueurs 404) est vérifié.
    """
    if status != 200:
        return False
    texte = extraire_texte_principal(html)
    if len(texte) < 200:
        return False
    bas = texte[:400].lower()
    if any(m in bas for m in _MARQUEURS_404):
        return False
    if ressemble_a_home(texte, home_texte):
        return False
    return type_page is None or a_marqueurs_type(texte, html, type_page)


# --------------------------------------------------------------------------- #
# Découverte + collecte.
# --------------------------------------------------------------------------- #
def _base_url(domaine: str) -> str:
    return f"https://{domaine}"


def _candidats(
    base: str, decouverts: dict[TypePage, list[str]], type_page: TypePage
) -> list[str]:
    """URLs candidates (découvertes d'abord, puis chemins types), dédupées."""
    ordonnes: list[str] = []
    vus: set[str] = set()
    for url in decouverts.get(type_page, []) + [
        base + chemin for chemin in CHEMINS_TYPES.get(type_page, ())
    ]:
        if url not in vus:
            vus.add(url)
            ordonnes.append(url)
    return ordonnes


async def _decouvrir(
    base: str, home_html: str, sitemap_urls: list[str]
) -> dict[TypePage, list[str]]:
    """Mappe type de page → URLs candidates découvertes (footer + sitemap)."""
    decouverts: dict[TypePage, list[str]] = {}
    for href, texte in parse_liens_footer(home_html):
        type_page = classifier_url(href, texte)
        if type_page is not None:
            decouverts.setdefault(type_page, []).append(urljoin(base + "/", href))
    for url in sitemap_urls:
        type_page = classifier_url(url)
        if type_page is not None:
            decouverts.setdefault(type_page, []).append(url)
    return decouverts


async def _traiter_type(
    c: Collecteur,
    fetcher: Fetcher,
    type_page: TypePage,
    candidats: list[str],
    home_texte: str | None,
) -> None:
    """Cherche une page significative parmi les candidats ; émet le signal."""
    signal_cle = PAGE_SIGNAUX.get(type_page)
    sources_consultees: list[str] = []
    nb_bloque = 0
    for url in candidats:
        res = await fetcher(url)
        sources_consultees.append(url)
        if res.bloque:
            nb_bloque += 1
            continue
        if not page_significative(
            res.text, res.status, type_page=type_page, home_texte=home_texte
        ):
            continue
        # Page trouvée : snapshot systématique + signal (sauf snapshot-seul).
        snap = await c.snapshot(
            url=url,
            type_page=type_page,
            contenu=extraire_texte_principal(res.text)[:20000],
            http_status=res.status,
            mode_acces=res.mode_acces,
        )
        if signal_cle is not None:
            critere, type_signal = signal_cle
            await c.signal(
                critere=critere,
                type_signal=type_signal,
                statut="present",
                valeur={"url": url, "detection": "page_type"},
                citation=None,
                source_urls=[url],
                snapshot_id=snap.id,
            )
        return

    if signal_cle is None:
        return  # snapshot-seul (à-propos / ours) : rien à signaler si absent
    critere, type_signal = signal_cle
    # Distinguer bloque_acces (tous les candidats consultés refusés) d'un
    # absent_verifie (au moins un 200 non significatif → la page n'existe pas).
    if sources_consultees and nb_bloque == len(sources_consultees):
        await c.bloque(
            critere=critere,
            type_signal=type_signal,
            url=sources_consultees[0],
            raison="tous les candidats bloqués (anti-bot) — présence indéterminée",
            sources_consultees=sources_consultees,
        )
        return
    await c.signal(
        critere=critere,
        type_signal=type_signal,
        statut="absent_verifie",
        valeur={"detection": "page_type", "bloque_rencontre": nb_bloque > 0},
        sources_consultees=sources_consultees,
    )


async def collecter(session, media, run, fetcher: Fetcher) -> CollectStats:
    """Découvre et détecte les pages types du média (voie A)."""
    c = await ouvrir_collecteur(session, media, run, COLLECTEUR)
    base = _base_url(media.domaine)

    home = await fetcher(base + "/")
    if home.bloque:
        # Home inaccessible : on émet un bloque_acces par signal attendu et on
        # s'arrête (rien à découvrir). « Jamais d'échec silencieux ».
        for type_page, (critere, type_signal) in PAGE_SIGNAUX.items():
            await c.bloque(
                critere=critere,
                type_signal=type_signal,
                url=base + "/",
                raison="home inaccessible (anti-bot) — découverte impossible",
                sources_consultees=[base + "/"],
            )
        return c.stats
    # Texte principal de la home : référence anti soft-404 (une page qui le
    # renvoie à l'identique est une coquille, cf. ``ressemble_a_home``).
    home_texte = extraire_texte_principal(home.text)
    await c.snapshot(
        url=base + "/",
        type_page=TypePage.AUTRE,
        contenu=home_texte[:20000],
        http_status=home.status,
        mode_acces=home.mode_acces,
    )

    sitemap = await fetcher(base + "/sitemap.xml")
    sitemap_urls = parse_sitemap(sitemap.text) if sitemap.ok else []
    decouverts = await _decouvrir(base, home.text, sitemap_urls)

    for type_page in (*PAGE_SIGNAUX.keys(), *PAGES_SNAPSHOT_SEUL):
        await _traiter_type(
            c, fetcher, type_page, _candidats(base, decouverts, type_page), home_texte
        )
    return c.stats


def main() -> None:
    run_cli("pages_types", collecter)


if __name__ == "__main__":
    main()
