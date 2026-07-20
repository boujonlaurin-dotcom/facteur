#!/usr/bin/env python3
"""Garde-fous mécaniques de la méthodo v1.2 — fonctions pures, codées en dur.

Jamais dans les prompts (architecture §6). Amont (`build_eval_input.py`) :
fraîcheur, raccourci JTI, déclencheur fallback C1. Aval
(`ingest_evaluations.py`) : corroboration, `bloque_acces` jamais 0, dérivation
du statut. Toutes les fonctions travaillent sur des dicts sérialisés (signaux)
pour être testables sans DB.
"""

from __future__ import annotations

from datetime import date
from urllib.parse import urlparse

from app.models.media_eval import StatutEvaluation, StatutSignal
from scripts.media_eval.schemas import (
    CORROBORATION_MIN_SOURCES,
    FALLBACK_C1_MIN_DEBUNKAGES,
    FLAG_CORROBORATION,
    VERSION_METHODO,
    grille,
    palier_inferieur,
)

# --------------------------------------------------------------------------- #
# Amont — fraîcheur (v1.2 §5.4 : événementiel borné, structurel constaté à date)
# --------------------------------------------------------------------------- #


def date_evenement(signal: dict) -> date | None:
    """Date de l'événement porté par un signal événementiel (C1)."""
    valeur = signal.get("valeur") or {}
    brut = valeur.get("publie_at") or valeur.get("date")
    if brut is None:
        return None
    if isinstance(brut, date):
        return brut
    return date.fromisoformat(str(brut)[:10])


def est_frais(
    signal: dict, aujourd_hui: date, version: str = VERSION_METHODO
) -> bool:
    """True si le signal peut fonder une notation à la date donnée.

    Les signaux structurels (chartes, registres…) sont constatés à date, sans
    limite d'ancienneté. Les signaux événementiels (types C1) doivent dater de
    moins de ``fraicheur_max_jours`` (v1.2 : 730 j ; v1.3 : 1095 j / 36 mois) ;
    sans date exploitable ils sont exclus (ils ne peuvent pas prouver leur
    fraîcheur).
    """
    g = grille(version)
    if signal.get("type_signal") not in g.types_evenementiels:
        return True
    quand = date_evenement(signal)
    if quand is None:
        return False
    return (aujourd_hui - quand).days <= g.fraicheur_max_jours


def filtrer_fraicheur(
    signaux: list[dict], aujourd_hui: date, version: str = VERSION_METHODO
) -> tuple[list[dict], list[dict]]:
    """Sépare (frais, exclus) — les exclus sont journalisés, jamais notés."""
    frais = [s for s in signaux if est_frais(s, aujourd_hui, version)]
    exclus = [s for s in signaux if not est_frais(s, aujourd_hui, version)]
    return frais, exclus


def fallback_c1_requis(nb_debunkages_frais: int) -> bool:
    """< 3 débunkages / 2 ans → vérification manuelle (N/A en V0)."""
    return nb_debunkages_frais < FALLBACK_C1_MIN_DEBUNKAGES


def detecter_jti_valide(signaux_c8: list[dict]) -> dict | None:
    """Raccourci JTI (v1.2) : certification présente et en cours de validité.

    Retourne le signal déclencheur, ou None. La validité est portée par
    ``valeur.en_cours_de_validite`` (renseignée par le collecteur registre).
    """
    for signal in signaux_c8:
        if (
            signal.get("type_signal") == "certification_jti"
            and signal.get("statut") == StatutSignal.PRESENT.value
            and (signal.get("valeur") or {}).get("en_cours_de_validite") is True
        ):
            return signal
    return None


# --------------------------------------------------------------------------- #
# Aval — corroboration (§5.2) + bloque_acces jamais 0 (arbitrage n°3)
# --------------------------------------------------------------------------- #


def _domaine_enregistrable(url: str) -> str | None:
    netloc = urlparse(url).netloc.lower().removeprefix("www.")
    return netloc or None


def compter_sources_independantes(signaux_cites: list[dict]) -> int:
    """Nombre de domaines distincts parmi les source_urls des signaux cités."""
    domaines = {
        d
        for s in signaux_cites
        for u in (s.get("source_urls") or [])
        if (d := _domaine_enregistrable(u))
    }
    return len(domaines)


def appliquer_corroboration(
    critere: str,
    score: float,
    signaux_cites: list[dict],
    version: str = VERSION_METHODO,
) -> tuple[float, list[str]]:
    """Score plein sans ≥ 2 sources indépendantes → palier inférieur + flag."""
    if score < grille(version).baremes[critere]:
        return score, []
    if compter_sources_independantes(signaux_cites) >= CORROBORATION_MIN_SOURCES:
        return score, []
    return palier_inferieur(critere, score, version), [FLAG_CORROBORATION]


def statut_evaluation(flags: list[str], signaux_cites: list[dict]) -> str:
    """Statut dérivé — `bloque_acces` n'est JAMAIS converti en 0.

    - flag ``donnees_insuffisantes`` → ``non_applicable`` (N/A, score NULL) ;
    - flag ``bloque_acces``, ou uniquement des signaux cités ``bloque_acces``
      → ``revue_requise`` (« non évaluable pour cause d'accès », score NULL) ;
    - sinon → ``evaluee``.
    """
    if "donnees_insuffisantes" in flags:
        return StatutEvaluation.NON_APPLICABLE.value
    if "bloque_acces" in flags:
        return StatutEvaluation.REVUE_REQUISE.value
    if signaux_cites and all(
        s.get("statut") == StatutSignal.BLOQUE_ACCES.value for s in signaux_cites
    ):
        return StatutEvaluation.REVUE_REQUISE.value
    return StatutEvaluation.EVALUEE.value
