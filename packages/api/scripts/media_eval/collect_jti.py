#!/usr/bin/env python3
"""Collecteur voie A — JTI (Journalism Trust Initiative, registre RSF).

Registre public des médias certifiés JTI → C8/``certification_jti`` :
- média présent et certification en cours de validité → ``present`` avec
  ``valeur.en_cours_de_validite=True`` (déclenche le **raccourci JTI** en aval :
  ``build_eval_input`` écrit l'éval C8 pleine par code, sans agent) ;
- sinon → ``absent_verifie`` (cas attendu des deux pilotes CNEWS/Reporterre).

Registre inaccessible → ``bloque_acces``.

Usage :
    cd packages/api
    python3 scripts/media_eval/collect_jti.py --media cnews.fr \
        --run-id pilote-2026-07 [--apply --allow-prod]
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from bs4 import BeautifulSoup

from scripts.media_eval.collect_common import (
    CollectStats,
    Fetcher,
    ouvrir_collecteur,
    run_cli,
)

COLLECTEUR = "code:collect_jti@v1"

URL_ANNUAIRE = "https://www.journalismtrustinitiative.org/evaluations"


def parse_jti_directory(html: str) -> list[dict]:
    """Médias certifiés : {nom, en_cours_de_validite} depuis l'annuaire.

    Un item marqué ``expiré``/``expired`` → validité fausse ; sinon vraie.
    """
    soup = BeautifulSoup(html, "html.parser")
    zone = soup.find(class_="jti-directory") or soup.find("main") or soup
    resultats: list[dict] = []
    for item in zone.find_all(["li", "tr"]):
        texte = item.get_text(" ", strip=True)
        if not texte:
            continue
        nom = item.get("data-media") or texte
        bas = texte.lower()
        valide = "expir" not in bas and "révoqu" not in bas and "revoqu" not in bas
        resultats.append({"nom": nom.strip(), "en_cours_de_validite": valide})
    return resultats


def chercher_media(nom_media: str, entrees: list[dict]) -> dict | None:
    cible = nom_media.strip().lower()
    for e in entrees:
        if cible in e["nom"].lower():
            return e
    return None


async def collecter(session, media, run, fetcher: Fetcher) -> CollectStats:
    """Certification JTI (C8) — present (validité) ou absent_verifie."""
    c = await ouvrir_collecteur(session, media, run, COLLECTEUR)
    res = await fetcher(URL_ANNUAIRE)
    if res.bloque or res.status != 200:
        await c.bloque(
            critere="C8",
            type_signal="certification_jti",
            url=URL_ANNUAIRE,
            raison="annuaire JTI inaccessible",
            sources_consultees=[URL_ANNUAIRE],
        )
        return c.stats

    entree = chercher_media(media.nom, parse_jti_directory(res.text))
    if entree is not None:
        await c.signal(
            critere="C8",
            type_signal="certification_jti",
            statut="present",
            valeur={
                "registre": "jti",
                "en_cours_de_validite": entree["en_cours_de_validite"],
                "url": URL_ANNUAIRE,
            },
            source_urls=[URL_ANNUAIRE],
        )
    else:
        await c.signal(
            critere="C8",
            type_signal="certification_jti",
            statut="absent_verifie",
            sources_consultees=[URL_ANNUAIRE],
        )
    return c.stats


def main() -> None:
    run_cli("jti", collecter)


if __name__ == "__main__":
    main()
