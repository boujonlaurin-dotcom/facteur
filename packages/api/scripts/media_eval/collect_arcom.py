#!/usr/bin/env python3
"""Collecteur voie A — ARCOM (décisions & sanctions de l'audiovisuel).

L'ARCOM ne régule que l'audiovisuel : si le média n'est **pas** audiovisuel,
le collecteur affiche « N/A structurel » et **n'écrit aucun signal** (l'absence
reste neutre — décision PO : ARCOM conservé dans le registre C1 mais N/A
structurel pour la presse en ligne). Reporterre → 0 signal.

Pour un média audiovisuel (CNEWS) : décisions/sanctions filtrées par média et
par fenêtre (``date_reference − 730 j``) → C1/``sanction_arcom`` present par
décision (``valeur.publie_at`` obligatoire), ou ``absent_verifie`` si aucune.
La voie A ne pose que le fait « une sanction existe » ; gravité et suite
donnée restent à l'agent debunkages (voie B). Fetch bloqué → ``bloque_acces``.

Usage :
    cd packages/api
    python3 scripts/media_eval/collect_arcom.py --media cnews.fr \
        --run-id pilote-2026-07 [--apply --allow-prod]
"""

from __future__ import annotations

import sys
from datetime import date, timedelta
from pathlib import Path
from urllib.parse import quote, urljoin

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from bs4 import BeautifulSoup

from app.models.media_eval import TypeMedia
from scripts.media_eval.collect_common import (
    CollectStats,
    Fetcher,
    ouvrir_collecteur,
    run_cli,
)
from scripts.media_eval.schemas import FRAICHEUR_MAX_JOURS

COLLECTEUR = "code:collect_arcom@v1"
URL_BASE = "https://www.arcom.fr"


def recherche_url(nom_media: str) -> str:
    return f"{URL_BASE}/nos-ressources/mediatheque?recherche={quote(nom_media)}"


def _parse_date(brut: str) -> date | None:
    brut = (brut or "").strip()
    if not brut:
        return None
    try:
        return date.fromisoformat(brut[:10])
    except ValueError:
        return None


def parse_arcom_decisions(html: str, base: str = URL_BASE) -> list[dict]:
    """Décisions listées : {url, titre, publie_at, media} depuis la recherche."""
    soup = BeautifulSoup(html, "html.parser")
    decisions: list[dict] = []
    for item in soup.find_all(class_="decision"):
        lien = item.find("a", href=True)
        if lien is None:
            continue
        time_tag = item.find("time")
        publie_at = None
        if time_tag is not None:
            publie_at = _parse_date(
                time_tag.get("datetime") or time_tag.get_text(strip=True)
            )
        decisions.append(
            {
                "url": urljoin(base + "/", lien["href"]),
                "titre": lien.get_text(" ", strip=True),
                "publie_at": publie_at,
                "media": (item.get("data-media") or "").strip(),
            }
        )
    return decisions


def concerne_media(decision: dict, nom_media: str) -> bool:
    cible = nom_media.strip().lower()
    return cible in decision["media"].lower() or cible in decision["titre"].lower()


async def collecter(session, media, run, fetcher: Fetcher) -> CollectStats:
    """Sanctions ARCOM (C1) — N/A structurel hors audiovisuel."""
    c = await ouvrir_collecteur(session, media, run, COLLECTEUR)

    if media.type_media != TypeMedia.AUDIOVISUEL:
        print(
            f"[arcom] N/A structurel : {media.domaine} n'est pas audiovisuel "
            f"({media.type_media}) — aucun signal (absence neutre)."
        )
        return c.stats

    url = recherche_url(media.nom)
    res = await fetcher(url)
    if res.bloque or res.status != 200:
        await c.bloque(
            critere="C1",
            type_signal="sanction_arcom",
            url=url,
            raison="médiathèque ARCOM inaccessible",
            sources_consultees=[url],
        )
        return c.stats

    cutoff = run.date_reference - timedelta(days=FRAICHEUR_MAX_JOURS)
    trouvees = 0
    for decision in parse_arcom_decisions(res.text):
        if not concerne_media(decision, media.nom):
            continue
        publie_at = decision["publie_at"]
        if publie_at is None or publie_at < cutoff:
            continue
        trouvees += 1
        await c.signal(
            critere="C1",
            type_signal="sanction_arcom",
            statut="present",
            valeur={
                "emetteur": "arcom",
                "publie_at": publie_at.isoformat(),
                "url": decision["url"],
                "titre": decision["titre"],
            },
            citation=decision["titre"],
            source_urls=[decision["url"]],
        )
    if trouvees == 0:
        await c.signal(
            critere="C1",
            type_signal="sanction_arcom",
            statut="absent_verifie",
            sources_consultees=[url],
        )
    return c.stats


def main() -> None:
    run_cli("arcom", collecter)


if __name__ == "__main__":
    main()
