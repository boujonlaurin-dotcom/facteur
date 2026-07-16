#!/usr/bin/env python3
"""Collecteur voie A — CDJM (Conseil de déontologie journalistique et médiation).

Deux registres publics de cdjm.org :
- **membres** → C8/``adhesion_cdjm`` (present si le média adhère, sinon
  ``absent_verifie``) ;
- **avis** → C1/``avis_cdjm`` : un signal *par avis fondé* concernant le média
  dans la fenêtre (``date_reference − 730 j``), avec ``valeur.publie_at``
  **obligatoire** (sinon la fraîcheur l'exclut en aval).

La voie A n'écrit **pas** de couple débunkage : gravité et suite donnée sont un
jugement, réservé à l'agent debunkages (voie B). Ici on ne pose que le fait
« un avis fondé existe ». Fetch bloqué / DOM cassé → ``bloque_acces``.

Usage :
    cd packages/api
    python3 scripts/media_eval/collect_cdjm.py --media cnews.fr \
        --run-id pilote-2026-07 [--apply --allow-prod]
"""

from __future__ import annotations

import sys
from datetime import date, timedelta
from pathlib import Path
from urllib.parse import urljoin

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from bs4 import BeautifulSoup

from scripts.media_eval.collect_common import (
    Collecteur,
    CollectStats,
    Fetcher,
    ouvrir_collecteur,
    run_cli,
)
from scripts.media_eval.schemas import FRAICHEUR_MAX_JOURS

COLLECTEUR = "code:collect_cdjm@v1"

URL_MEMBRES = "https://cdjm.org/les-membres/"
URL_AVIS_INDEX = "https://cdjm.org/nos-avis/"


# --------------------------------------------------------------------------- #
# Fonctions pures.
# --------------------------------------------------------------------------- #
def parse_membres(html: str) -> list[str]:
    """Noms des médias membres (texte des items de la liste des membres)."""
    soup = BeautifulSoup(html, "html.parser")
    zone = soup.find(class_="membres") or soup.find("main") or soup
    noms = []
    for item in zone.find_all(["li", "a", "h3"]):
        texte = item.get_text(" ", strip=True)
        if texte and len(texte) < 120:
            noms.append(texte)
    return noms


def parse_avis_index(html: str, base: str = URL_AVIS_INDEX) -> list[dict]:
    """Liste des avis (url absolue, titre) depuis l'index."""
    soup = BeautifulSoup(html, "html.parser")
    avis: list[dict] = []
    vus: set[str] = set()
    for a in soup.find_all("a", href=True):
        href = a["href"].strip()
        if "avis" not in href.lower():
            continue
        url = urljoin(base, href)
        if url in vus or url.rstrip("/") == base.rstrip("/"):
            continue
        vus.add(url)
        avis.append({"url": url, "titre": a.get_text(" ", strip=True)})
    return avis


def _texte_date(valeur: str) -> date | None:
    valeur = valeur.strip()
    for fmt in ("%Y-%m-%d",):
        try:
            return date.fromisoformat(valeur[:10])
        except ValueError:
            pass
    return None


def parse_avis_detail(html: str) -> dict:
    """Extrait {publie_at, fonde, media, resume} d'une page d'avis.

    ``publie_at`` : balise <time datetime="…">. ``fonde`` : présence du mot
    « fondé(e) » dans le verdict. ``media`` : bloc « média mis en cause ».
    """
    soup = BeautifulSoup(html, "html.parser")
    time_tag = soup.find("time")
    publie_at = None
    if time_tag is not None:
        brut = time_tag.get("datetime") or time_tag.get_text(strip=True)
        publie_at = _texte_date(brut or "")
    texte = soup.get_text(" ", strip=True).lower()
    fonde = "fondé" in texte or "fondee" in texte or "fondée" in texte
    media = None
    mis_en_cause = soup.find(class_="media-mis-en-cause")
    if mis_en_cause is not None:
        media = mis_en_cause.get_text(" ", strip=True)
    titre = soup.find(["h1", "title"])
    resume = titre.get_text(" ", strip=True) if titre else None
    return {"publie_at": publie_at, "fonde": fonde, "media": media, "resume": resume}


def media_est_membre(nom_media: str, membres: list[str]) -> bool:
    cible = nom_media.strip().lower()
    return any(cible in m.lower() for m in membres)


def avis_concerne_media(
    entree: dict, nom_media: str, detail: dict | None = None
) -> bool:
    cible = nom_media.strip().lower()
    if cible in (entree.get("titre") or "").lower():
        return True
    return bool(detail and cible in (detail.get("media") or "").lower())


# --------------------------------------------------------------------------- #
# Collecte.
# --------------------------------------------------------------------------- #
async def _collecter_adhesion(c: Collecteur, fetcher: Fetcher) -> None:
    res = await fetcher(URL_MEMBRES)
    if res.bloque or res.status != 200:
        await c.bloque(
            critere="C8",
            type_signal="adhesion_cdjm",
            url=URL_MEMBRES,
            raison="registre des membres CDJM inaccessible",
            sources_consultees=[URL_MEMBRES],
        )
        return
    membres = parse_membres(res.text)
    if media_est_membre(c.media.nom, membres):
        await c.signal(
            critere="C8",
            type_signal="adhesion_cdjm",
            statut="present",
            valeur={"registre": "cdjm", "url": URL_MEMBRES},
            source_urls=[URL_MEMBRES],
        )
    else:
        await c.signal(
            critere="C8",
            type_signal="adhesion_cdjm",
            statut="absent_verifie",
            sources_consultees=[URL_MEMBRES],
        )


async def _collecter_avis(c: Collecteur, fetcher: Fetcher, cutoff: date) -> None:
    res = await fetcher(URL_AVIS_INDEX)
    if res.bloque or res.status != 200:
        await c.bloque(
            critere="C1",
            type_signal="avis_cdjm",
            url=URL_AVIS_INDEX,
            raison="index des avis CDJM inaccessible",
            sources_consultees=[URL_AVIS_INDEX],
        )
        return
    for entree in parse_avis_index(res.text):
        # On ne consulte le détail que si le titre mentionne le média.
        if not avis_concerne_media(entree, c.media.nom):
            continue
        detail_res = await fetcher(entree["url"])
        if detail_res.bloque or detail_res.status != 200:
            await c.bloque(
                critere="C1",
                type_signal="avis_cdjm",
                url=entree["url"],
                raison="page d'avis CDJM inaccessible",
                sources_consultees=[entree["url"]],
            )
            continue
        detail = parse_avis_detail(detail_res.text)
        publie_at = detail["publie_at"]
        if not detail["fonde"] or publie_at is None or publie_at < cutoff:
            continue
        await c.signal(
            critere="C1",
            type_signal="avis_cdjm",
            statut="present",
            valeur={
                "emetteur": "cdjm",
                "publie_at": publie_at.isoformat(),
                "url": entree["url"],
                "fonde": True,
                "resume": detail["resume"],
            },
            citation=detail["resume"],
            source_urls=[entree["url"]],
        )


async def collecter(session, media, run, fetcher: Fetcher) -> CollectStats:
    """Adhésion CDJM (C8) + avis fondés dans la fenêtre (C1)."""
    c = await ouvrir_collecteur(session, media, run, COLLECTEUR)
    cutoff = run.date_reference - timedelta(days=FRAICHEUR_MAX_JOURS)
    await _collecter_adhesion(c, fetcher)
    await _collecter_avis(c, fetcher, cutoff)
    return c.stats


def main() -> None:
    run_cli("cdjm", collecter)


if __name__ == "__main__":
    main()
