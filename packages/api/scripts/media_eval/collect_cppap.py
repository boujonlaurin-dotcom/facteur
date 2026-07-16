#!/usr/bin/env python3
"""Collecteur voie A — CPPAP (Commission paritaire des publications et agences).

D5 : **open data uniquement** — dataset ``liste-des-publications-de-presse`` de
data.culture.gouv.fr (API Explore v2.1), qui liste les titres de presse et leur
``ndeg_cppap`` — jamais le formulaire POST du site cppap. Le numéro CPPAP est un
signal de transparence légale → C5/``enregistrement_cppap`` :
- titre trouvé dans le dataset → ``present`` (``valeur.numero_cppap``) ;
- recherche aboutie mais aucun résultat → ``absent_verifie`` (cas attendu d'un
  média purement audiovisuel comme CNEWS : pas de publication de presse) ;
- dataset inaccessible → ``bloque_acces``. **Repli voie C** : si le portail est
  durablement down, un artefact humain (``agent: "humain:laurin"``) peut poser
  ``enregistrement_cppap`` avec le n° CPPAP (ou l'ISSN, ex. 2669-7432 pour
  CNEWS) lu dans le snapshot des mentions légales (cf. D6).

Toute réponse non exploitable est traitée comme un accès bloqué (jamais
d'exception).

Usage :
    cd packages/api
    python3 scripts/media_eval/collect_cppap.py --media cnews.fr \
        --run-id pilote-2026-07 [--apply --allow-prod]
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from urllib.parse import quote

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from scripts.media_eval.collect_common import (
    CollectStats,
    Fetcher,
    ouvrir_collecteur,
    run_cli,
)

COLLECTEUR = "code:collect_cppap@v1"

# API Explore v2.1 (Opendatasoft, data.culture.gouv.fr). Slug + champs confirmés
# le 2026-07 : dataset ``liste-des-publications-de-presse`` (titre, ndeg_cppap).
DATASET = "liste-des-publications-de-presse"
URL_BASE = (
    f"https://data.culture.gouv.fr/api/explore/v2.1/catalog/datasets/{DATASET}/records"
)

_CHAMPS_TITRE = ("titre", "titre_de_presse", "nom", "publication")
_CHAMPS_NUMERO = ("numero_cppap", "ndeg_cppap", "numero", "cppap", "n_cppap")


def cppap_url(nom_media: str) -> str:
    # Recherche plein-texte v2.1 : une phrase entre guillemets dans ``where``.
    where = quote(f'"{nom_media}"')
    return f"{URL_BASE}?where={where}&limit=50"


def parse_cppap_records(texte: str) -> list[dict]:
    """Normalise la réponse (ODS v1 ``records[].fields`` ou liste brute).

    Retourne des dicts ``{titre, numero_cppap}``. Une réponse non-JSON lève
    ``ValueError`` (le collecteur la traite en ``bloque_acces``).
    """
    data = json.loads(texte)
    if isinstance(data, dict):
        bruts = data.get("records") or data.get("results") or []
    else:
        bruts = data
    normalises: list[dict] = []
    for rec in bruts:
        champs = rec.get("fields", rec) if isinstance(rec, dict) else {}
        titre = next((champs[c] for c in _CHAMPS_TITRE if champs.get(c)), None)
        numero = next((champs[c] for c in _CHAMPS_NUMERO if champs.get(c)), None)
        if titre:
            normalises.append({"titre": str(titre), "numero_cppap": numero})
    return normalises


def chercher_titre(nom_media: str, records: list[dict]) -> dict | None:
    cible = nom_media.strip().lower()
    for rec in records:
        if cible in rec["titre"].lower():
            return rec
    return None


async def collecter(session, media, run, fetcher: Fetcher) -> CollectStats:
    """Enregistrement CPPAP (C5) via open data."""
    c = await ouvrir_collecteur(session, media, run, COLLECTEUR)
    url = cppap_url(media.nom)
    res = await fetcher(url)
    if res.bloque or res.status != 200:
        await c.bloque(
            critere="C5",
            type_signal="enregistrement_cppap",
            url=url,
            raison="dataset CPPAP open data inaccessible",
            sources_consultees=[url],
        )
        return c.stats
    try:
        records = parse_cppap_records(res.text)
    except (ValueError, TypeError):
        await c.bloque(
            critere="C5",
            type_signal="enregistrement_cppap",
            url=url,
            raison="réponse CPPAP non exploitable (format inattendu)",
            sources_consultees=[url],
        )
        return c.stats

    trouve = chercher_titre(media.nom, records)
    if trouve is not None:
        await c.signal(
            critere="C5",
            type_signal="enregistrement_cppap",
            statut="present",
            valeur={
                "numero_cppap": trouve["numero_cppap"],
                "titre": trouve["titre"],
                "source": "data.culture.gouv.fr",
            },
            source_urls=[url],
        )
    else:
        await c.signal(
            critere="C5",
            type_signal="enregistrement_cppap",
            statut="absent_verifie",
            sources_consultees=[url],
        )
    return c.stats


def main() -> None:
    run_cli("cppap", collecter)


if __name__ == "__main__":
    main()
