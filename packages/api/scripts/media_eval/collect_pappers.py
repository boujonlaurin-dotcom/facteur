#!/usr/bin/env python3
"""Collecteur voie A — Pappers (registre du commerce, propriété & capital).

Interroge l'API ``api.pappers.fr/v2/entreprise`` sur un SIREN **codé en dur**
par média (l'éditeur, jamais deviné à la volée) et pose trois signaux :
- C5/``identification_proprietaire`` (raison sociale, SIREN, dirigeants) ;
- C5/``structure_actionnariat`` (bénéficiaires effectifs) ;
- C9/``independance_capital`` (concentration du capital — substance jugée par
  l'évaluateur, on ne pose que le fait).

Garde-fou ``verifier_entreprise`` : si la raison sociale renvoyée ne
correspond pas à celle attendue pour le SIREN, on **lève** (``CollecteError``)
plutôt que d'attribuer les données d'une autre société.

**Token absent ou épuisé** (``PAPPERS_API_TOKEN``) → repli sur l'API publique
**gratuite** ``recherche-entreprises.api.gouv.fr`` (sans auth) :
``identification_proprietaire`` ``present`` (raison sociale + dirigeants) et
``structure_actionnariat`` / ``independance_capital`` ``partiel`` (les
bénéficiaires effectifs ne sont pas exposés par l'API gratuite), au lieu de 3
``bloque_acces``. SIREN non référencé pour le média, ou repli lui aussi
inaccessible → ``bloque_acces``. Tous ces cas gardent exit 0 (run valide).

Usage :
    cd packages/api
    PAPPERS_API_TOKEN=xxx python3 scripts/media_eval/collect_pappers.py \
        --media cnews.fr --run-id pilote-2026-07 [--apply --allow-prod]
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from urllib.parse import quote

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from scripts.media_eval.collect_common import (
    CollecteError,
    Collecteur,
    CollectStats,
    Fetcher,
    ouvrir_collecteur,
    run_cli,
)

COLLECTEUR = "code:collect_pappers@v1"
URL_BASE = "https://api.pappers.fr/v2/entreprise"
# API publique gratuite (Annuaire des Entreprises) — sans auth, repli sans token.
URL_RECHERCHE_ENTREPRISES = "https://recherche-entreprises.api.gouv.fr/search"

# Éditeur **du site** de chaque média pilote (SIREN + raison sociale attendue).
# CNEWS : l'éditeur du site cnews.fr est **SESI SNC, RCS Nanterre 412 916 215**
# (lu dans ses mentions légales — capital 7 500 €), distinct de la société
# d'exploitation de la chaîne TV. Reporterre : association « La Pila ».
SIREN_MEDIAS: dict[str, dict[str, str]] = {
    "cnews.fr": {
        "siren": "412916215",
        "raison_sociale": "SESI",
    },
    "reporterre.net": {
        "siren": "801054247",
        "raison_sociale": "LA PILA",
    },
}

# Les 3 signaux posés par ce collecteur (utilisés pour le repli bloque_acces).
_SIGNAUX = (
    ("C5", "identification_proprietaire"),
    ("C5", "structure_actionnariat"),
    ("C9", "independance_capital"),
)


def pappers_url(siren: str, token: str) -> str:
    return f"{URL_BASE}?api_token={quote(token)}&siren={quote(siren)}"


def recherche_entreprises_url(siren: str) -> str:
    return f"{URL_RECHERCHE_ENTREPRISES}?q={quote(siren)}&page=1&per_page=5"


def parse_recherche_entreprises(texte: str, siren: str) -> dict | None:
    """Normalise la réponse de l'API gratuite pour le SIREN cible.

    Retourne ``{nom, siren, dirigeants}`` du résultat au SIREN exact, ou
    ``None`` si aucun (on ne pose alors aucun signal). Réponse non-JSON →
    ``ValueError`` (traitée en ``bloque_acces`` par l'appelant).
    """
    data = json.loads(texte)
    for rec in data.get("results") or []:
        if str(rec.get("siren")) != str(siren):
            continue
        dirigeants = [
            {
                "nom": (
                    f"{d.get('prenoms', '')} {d.get('nom', '')}".strip()
                    or d.get("denomination")
                ),
                "qualite": d.get("qualite"),
            }
            for d in (rec.get("dirigeants") or [])
        ]
        return {
            "nom": rec.get("nom_complet") or rec.get("nom_raison_sociale"),
            "siren": str(rec.get("siren")),
            "dirigeants": dirigeants,
        }
    return None


def _normaliser(nom: str) -> str:
    table = str.maketrans("ÀÂÄÉÈÊËÎÏÔÖÙÛÜÇ", "AAAEEEEIIOOUUUC")
    return " ".join(nom.upper().translate(table).replace("'", " ").split())


def verifier_entreprise(payload: dict, raison_sociale_attendue: str) -> None:
    """Lève si la société renvoyée ≠ celle attendue (anti-attribution erronée)."""
    nom = _normaliser(str(payload.get("nom_entreprise") or payload.get("nom") or ""))
    attendu = _normaliser(raison_sociale_attendue)
    if not nom:
        raise CollecteError("réponse Pappers sans nom d'entreprise")
    # Tolérance : acronyme (SESI) OU chevauchement de tokens distinctifs.
    tokens_attendus = {t for t in attendu.split() if len(t) > 2}
    tokens_recus = set(nom.split())
    acronyme = "".join(t[0] for t in attendu.split() if t)
    if (
        attendu in nom
        or nom in attendu
        or acronyme in tokens_recus
        or len(tokens_attendus & tokens_recus) >= max(1, len(tokens_attendus) // 2)
    ):
        return
    raise CollecteError(
        f"raison sociale Pappers {nom!r} ≠ attendue {attendu!r} — "
        "SIREN possiblement obsolète, collecte interrompue."
    )


def parse_pappers(texte: str) -> dict:
    """Normalise la réponse v2 : {nom, siren, representants, beneficiaires}."""
    data = json.loads(texte)
    representants = [
        {"nom": r.get("nom_complet") or r.get("nom"), "qualite": r.get("qualite")}
        for r in (data.get("representants") or [])
    ]
    beneficiaires = [
        {
            "nom": b.get("nom_complet") or b.get("nom"),
            "pourcentage_parts": b.get("pourcentage_parts"),
        }
        for b in (data.get("beneficiaires_effectifs") or [])
    ]
    return {
        "nom_entreprise": data.get("nom_entreprise") or data.get("nom"),
        "siren": data.get("siren"),
        "capital": data.get("capital"),
        "representants": representants,
        "beneficiaires_effectifs": beneficiaires,
    }


async def _bloque_tous(c: Collecteur, url: str | None, raison: str) -> None:
    for critere, type_signal in _SIGNAUX:
        await c.bloque(
            critere=critere,
            type_signal=type_signal,
            url=url,
            raison=raison,
            sources_consultees=[url] if url else [],
        )


async def _via_pappers(
    c: Collecteur, ref: dict[str, str], token: str, fetcher: Fetcher
) -> bool:
    """Voie Pappers (substance complète). Retourne True si 3 signaux posés.

    Accès refusé / réponse non exploitable → False (l'appelant tente le repli
    gratuit). Raison sociale ≠ attendue → **lève** (anti-attribution erronée).
    """
    res = await fetcher(pappers_url(ref["siren"], token))
    if res.bloque or res.status != 200:
        return False
    try:
        data = json.loads(res.text)
    except (ValueError, TypeError):
        return False

    verifier_entreprise(data, ref["raison_sociale"])  # lève si mismatch
    info = parse_pappers(res.text)
    source = f"https://www.pappers.fr/entreprise/{ref['siren']}"
    await c.signal(
        critere="C5",
        type_signal="identification_proprietaire",
        statut="present",
        valeur={
            "raison_sociale": info["nom_entreprise"],
            "siren": info["siren"],
            "representants": info["representants"],
        },
        source_urls=[source],
    )
    await c.signal(
        critere="C5",
        type_signal="structure_actionnariat",
        statut="present" if info["beneficiaires_effectifs"] else "partiel",
        valeur={
            "capital": info["capital"],
            "beneficiaires_effectifs": info["beneficiaires_effectifs"],
        },
        source_urls=[source],
    )
    await c.signal(
        critere="C9",
        type_signal="independance_capital",
        statut="present",
        valeur={
            "capital": info["capital"],
            "beneficiaires_effectifs": info["beneficiaires_effectifs"],
        },
        source_urls=[source],
    )
    return True


async def _via_recherche_entreprises(
    c: Collecteur, ref: dict[str, str], fetcher: Fetcher
) -> bool:
    """Repli gratuit (Annuaire des Entreprises). Retourne True si signaux posés.

    L'API gratuite donne la raison sociale + les dirigeants (→
    ``identification_proprietaire`` ``present``) mais **pas** les bénéficiaires
    effectifs ni la concentration du capital (→ ``structure_actionnariat`` et
    ``independance_capital`` ``partiel``, jamais ``present``).
    """
    res = await fetcher(recherche_entreprises_url(ref["siren"]))
    if res.bloque or res.status != 200:
        return False
    try:
        info = parse_recherche_entreprises(res.text, ref["siren"])
    except (ValueError, TypeError):
        return False
    if info is None:
        return False

    source = f"https://annuaire-entreprises.data.gouv.fr/entreprise/{ref['siren']}"
    note = (
        "bénéficiaires effectifs et concentration du capital non exposés par "
        "l'API gratuite (Pappers requis pour la substance complète)"
    )
    await c.signal(
        critere="C5",
        type_signal="identification_proprietaire",
        statut="present",
        valeur={
            "raison_sociale": info["nom"],
            "siren": info["siren"],
            "dirigeants": info["dirigeants"],
            "source": "recherche-entreprises.api.gouv.fr",
        },
        source_urls=[source],
    )
    await c.signal(
        critere="C5",
        type_signal="structure_actionnariat",
        statut="partiel",
        valeur={"beneficiaires_effectifs": None, "note": note},
        source_urls=[source],
    )
    await c.signal(
        critere="C9",
        type_signal="independance_capital",
        statut="partiel",
        valeur={"concentration_capital": None, "note": note},
        source_urls=[source],
    )
    return True


async def collecter(session, media, run, fetcher: Fetcher) -> CollectStats:
    """Propriété / actionnariat / capital (C5, C5, C9) — Pappers ou repli gratuit."""
    c = await ouvrir_collecteur(session, media, run, COLLECTEUR)

    ref = SIREN_MEDIAS.get(media.domaine)
    if ref is None:
        print(f"[pappers] WARNING : aucun SIREN référencé pour {media.domaine}.")
        await _bloque_tous(c, None, "SIREN éditeur non référencé (voir SIREN_MEDIAS)")
        return c.stats

    token = os.environ.get("PAPPERS_API_TOKEN")
    if token:
        if await _via_pappers(c, ref, token, fetcher):
            return c.stats
        print(
            "[pappers] WARNING : API Pappers inaccessible/épuisée → repli sur "
            "recherche-entreprises.api.gouv.fr (gratuit, sans auth)."
        )
    else:
        print(
            "[pappers] WARNING : PAPPERS_API_TOKEN absent → repli sur "
            "recherche-entreprises.api.gouv.fr (gratuit). Le run reste valide."
        )

    if await _via_recherche_entreprises(c, ref, fetcher):
        return c.stats
    await _bloque_tous(c, URL_BASE, "Pappers et API entreprises gratuite inaccessibles")
    return c.stats


def main() -> None:
    run_cli("pappers", collecter)


if __name__ == "__main__":
    main()
