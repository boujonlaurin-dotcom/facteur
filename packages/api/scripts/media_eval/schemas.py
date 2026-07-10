#!/usr/bin/env python3
"""Contrats Pydantic + constantes du pipeline media-eval (C1–C11).

Source de vérité **codée en dur** des règles mécaniques de la méthodo v1.2
(cf. docs/media-eval/) : barèmes, registre des types de signaux, dérivation du
score depuis les `determinations` de l'évaluateur, dérivation du poids
émetteur des débunkages. Rien de tout cela n'est confié aux prompts — même
philosophie que `derive_reliability` dans `scripts/source_eval_schema.py`.

Les artefacts JSON produits par les agents (voie B + évaluateurs) sont validés
ici AVANT toute écriture DB (`ingest_artifacts.py`, `ingest_evaluations.py`) :
un artefact invalide est rejeté en bloc, rien n'est écrit.
"""

from __future__ import annotations

from datetime import date, datetime

from pydantic import BaseModel, Field, field_validator, model_validator

from app.models.media_eval import (
    GraviteDebunkage,
    PoidsEmetteur,
    StatutSignal,
    SuiteDonnee,
)

VERSION_METHODO = "v1.2"

# --------------------------------------------------------------------------- #
# Barèmes (méthodo §4, verbatim) — jamais dans les prompts.
# --------------------------------------------------------------------------- #
BAREMES: dict[str, int] = {
    "C1": 20,
    "C2": 15,
    "C3": 10,
    "C4": 5,
    "C5": 10,
    "C6": 6,
    "C7": 4,
    "C8": 4,
    "C9": 10,
    "C10": 10,
    "C11": 6,
}  # total 100
assert sum(BAREMES.values()) == 100

CRITERES_VAGUE_1: tuple[str, ...] = ("C1", "C5", "C7", "C8", "C9", "C11")  # 54 pts
CRITERES_NIVEAUX: tuple[str, ...] = ("C9", "C11")  # échelles à 3 niveaux en vague 1

# Scores par niveau (méthodo §4.2/§4.3, verbatim).
NIVEAU_SCORES: dict[str, dict[int, int]] = {
    "C9": {0: 0, 1: 5, 2: 10},
    "C11": {0: 0, 1: 3, 2: 6},
}

# Lettres A–E sur le score renormalisé /100 (méthodo §4.4.1 — seuils PO,
# à confirmer à l'import de la v1.2 finale).
LETTRES: list[tuple[int, str]] = [(85, "A"), (70, "B"), (55, "C"), (40, "D"), (0, "E")]

# Garde-fous mécaniques (architecture §6).
FRAICHEUR_MAX_JOURS = 730
FALLBACK_C1_MIN_DEBUNKAGES = 3
CORROBORATION_MIN_SOURCES = 2

# Échelle de scores possibles par critère (vague 1) : sert au plafonnement
# « palier inférieur » du garde-fou de corroboration.
PALIERS: dict[str, tuple[int, ...]] = {
    "C1": (0, 5, 10, 15, 20),
    "C5": (0, 5, 10),
    "C7": (0, 2, 4),
    "C8": (0, 2, 4),
    "C9": (0, 5, 10),
    "C11": (0, 3, 6),
}

# Pondération des émetteurs de débunkages (amendement v1.2 C1) — dérivée par
# code depuis l'émetteur normalisé, jamais choisie par l'agent. Les rubriques
# de fact-checking de médias concurrents directs = poids réduit (conflit
# d'intérêts potentiel documenté). Émetteur inconnu -> `faible`.
POIDS_EMETTEUR: dict[str, str] = {
    "arcom": PoidsEmetteur.FORT.value,
    "justice": PoidsEmetteur.FORT.value,
    "cdjm": PoidsEmetteur.FORT.value,
    "afp_factuel": PoidsEmetteur.MOYEN.value,
    "les_decodeurs": PoidsEmetteur.MOYEN.value,
    "checknews": PoidsEmetteur.MOYEN.value,
    "factuel_franceinfo": PoidsEmetteur.MOYEN.value,
    "fake_off": PoidsEmetteur.MOYEN.value,
}
POIDS_EMETTEUR_DEFAUT = PoidsEmetteur.FAIBLE.value


def derive_poids_emetteur(emetteur: str) -> str:
    """Poids d'un émetteur de débunkage (clé normalisée snake_case)."""
    return POIDS_EMETTEUR.get(emetteur.strip().lower(), POIDS_EMETTEUR_DEFAUT)


# --------------------------------------------------------------------------- #
# Registre des types de signaux (vague 1, figé).
# --------------------------------------------------------------------------- #
TYPE_SIGNAUX: dict[str, tuple[str, ...]] = {
    "C1": ("debunkage", "sanction_arcom", "condamnation_justice", "avis_cdjm"),
    "C5": (
        "mentions_legales",
        "identification_proprietaire",
        "structure_actionnariat",
        "enregistrement_cppap",
        "transparence_financement",
    ),
    "C7": (
        "marquage_contenu_sponsorise",
        "regie_pub_identifiee",
        "politique_publicitaire",
    ),
    "C8": (
        "charte_deontologique",
        "adhesion_cdjm",
        "certification_jti",
        "reference_charte_externe",
    ),
    "C9": (
        "charte_independance",
        "societe_journalistes",
        "independance_capital",
        "intervention_actionnaire",
        "statuts_redaction",
    ),
    "C11": (
        "manifeste_positionnement",
        "ligne_editoriale_publiee",
        "auto_description_orientation",
        "rubriques_opinion_identifiees",
    ),
}

# Types de signaux « événementiels » (fenêtre de fraîcheur 730 j) vs
# « structurels » (constatés à date, sans limite d'ancienneté) — v1.2 §5.4.
TYPES_EVENEMENTIELS: frozenset[str] = frozenset(TYPE_SIGNAUX["C1"])

# --------------------------------------------------------------------------- #
# Flags évaluateur (contrat `_common.md`) + flags posés par code.
# --------------------------------------------------------------------------- #
FLAGS_EVALUATEUR: frozenset[str] = frozenset(
    {
        "donnees_insuffisantes",
        "signaux_contradictoires",
        "bloque_acces",
        "revue_humaine_requise",
    }
)
FLAG_CORROBORATION = "corroboration_insuffisante"  # posé par code (aval)
FLAG_FALLBACK_C1 = "fallback_c1_declenche"  # posé par code (amont)

# Déterminations énumérables par critère (rubriques `docs/media-eval/rubrics/`).
C1_PROFILS: dict[str, int] = {
    "aucun_signal_negatif": 20,
    "problemes_mineurs_corriges": 15,
    "problemes_mixtes": 10,
    "problemes_significatifs": 5,
    "fabrication_ou_refus_non_corrige": 0,
}
# Notation méthodo §5.3-É2 (continue) : plein / 50 % / 0.
PROFILS_SIGNAUX: tuple[str, ...] = ("positifs_majoritaires", "mixtes", "negatifs")


def derive_score(critere: str, determinations: dict) -> tuple[float, int | None]:
    """Score faisant foi, dérivé par code depuis les `determinations`.

    Retourne ``(score, niveau)`` — ``niveau`` renseigné pour C9/C11, None
    sinon. Lève ``ValueError`` si les déterminations ne respectent pas la
    rubrique (mêmes règles que la validation `EvaluationOutput`).
    """
    if critere in CRITERES_NIVEAUX:
        niveau = determinations.get("niveau")
        if niveau not in (0, 1, 2):
            raise ValueError(f"{critere}: niveau invalide {niveau!r} (attendu 0|1|2)")
        return float(NIVEAU_SCORES[critere][niveau]), niveau
    if critere == "C1":
        profil = determinations.get("profil_veracite")
        if profil not in C1_PROFILS:
            raise ValueError(f"C1: profil_veracite invalide {profil!r}")
        return float(C1_PROFILS[profil]), None
    if critere in ("C5", "C7", "C8"):
        profil = determinations.get("profil_signaux")
        if profil not in PROFILS_SIGNAUX:
            raise ValueError(f"{critere}: profil_signaux invalide {profil!r}")
        plein = float(BAREMES[critere])
        return {"positifs_majoritaires": plein, "mixtes": plein / 2, "negatifs": 0.0}[
            profil
        ], None
    raise ValueError(f"critère hors vague 1 : {critere!r}")


def palier_inferieur(critere: str, score: float) -> float:
    """Palier immédiatement inférieur au score (garde-fou corroboration)."""
    paliers = PALIERS[critere]
    inferieurs = [p for p in paliers if p < score]
    return float(inferieurs[-1]) if inferieurs else 0.0


# --------------------------------------------------------------------------- #
# Artefacts voie B (collecteurs) — validés avant insertion.
# --------------------------------------------------------------------------- #
_STATUTS_SANS_SOURCE = {
    StatutSignal.ABSENT_VERIFIE.value,
    StatutSignal.BLOQUE_ACCES.value,
}


class SignalArtifact(BaseModel):
    """Un signal proposé par un agent collecteur (jamais écrit tel quel)."""

    media_domaine: str
    critere: str
    type_signal: str
    statut: str
    valeur: dict | None = None
    citation: str | None = None
    source_urls: list[str] = Field(default_factory=list)
    sources_consultees: list[str] = Field(default_factory=list)

    @field_validator("statut")
    @classmethod
    def _statut_valide(cls, v: str) -> str:
        if v not in {s.value for s in StatutSignal}:
            raise ValueError(f"statut hors enum: {v!r}")
        return v

    @model_validator(mode="after")
    def _coherence(self) -> SignalArtifact:
        registre = TYPE_SIGNAUX.get(self.critere)
        if registre is None:
            raise ValueError(f"critère hors vague 1 : {self.critere!r}")
        if self.type_signal not in registre:
            raise ValueError(
                f"type_signal {self.type_signal!r} hors registre {self.critere}"
            )
        if self.statut not in _STATUTS_SANS_SOURCE and not self.source_urls:
            raise ValueError(
                f"source_urls vide interdit pour statut {self.statut!r} "
                "(exigé sauf absent_verifie / bloque_acces)"
            )
        if (
            self.statut == StatutSignal.ABSENT_VERIFIE.value
            and not self.sources_consultees
        ):
            raise ValueError(
                "absent_verifie exige sources_consultees (preuve de recherche)"
            )
        return self


class DebunkageArtifact(BaseModel):
    """Un débunkage qualifié par un agent (C1).

    ``poids_emetteur`` est **dérivé par code** (`derive_poids_emetteur`) —
    toute valeur fournie par l'agent est ignorée. L'ingestion crée le couple
    débunkage + signal C1 (contrat évaluateur uniforme).
    """

    media_domaine: str
    type_signal: str = "debunkage"
    url_debunkage: str
    emetteur: str
    gravite: str
    suite_donnee: str
    publie_at: date
    resume: str | None = None
    citation: str | None = None
    source_urls: list[str] = Field(min_length=1)
    sources_consultees: list[str] = Field(default_factory=list)

    @field_validator("type_signal")
    @classmethod
    def _type_c1(cls, v: str) -> str:
        if v not in TYPE_SIGNAUX["C1"]:
            raise ValueError(f"type_signal {v!r} hors registre C1")
        return v

    @field_validator("gravite")
    @classmethod
    def _gravite_valide(cls, v: str) -> str:
        if v not in {g.value for g in GraviteDebunkage}:
            raise ValueError(f"gravite hors enum: {v!r}")
        return v

    @field_validator("suite_donnee")
    @classmethod
    def _suite_valide(cls, v: str) -> str:
        if v not in {s.value for s in SuiteDonnee}:
            raise ValueError(f"suite_donnee hors enum: {v!r}")
        return v

    def poids_emetteur(self) -> str:
        return derive_poids_emetteur(self.emetteur)


# --------------------------------------------------------------------------- #
# Sortie évaluateur — score dérivé par code, signal_ids obligatoires.
# --------------------------------------------------------------------------- #
class EvaluationOutput(BaseModel):
    """Sortie d'un agent évaluateur pour (média, critère)."""

    media_domaine: str
    critere: str
    determinations: dict = Field(default_factory=dict)
    justification: str
    signal_ids_cites: list[str] = Field(default_factory=list)
    flags: list[str] = Field(default_factory=list)

    @field_validator("flags")
    @classmethod
    def _flags_valides(cls, v: list[str]) -> list[str]:
        inconnus = set(v) - FLAGS_EVALUATEUR
        if inconnus:
            raise ValueError(f"flags hors contrat: {sorted(inconnus)}")
        return v

    @model_validator(mode="after")
    def _coherence(self) -> EvaluationOutput:
        if self.critere not in CRITERES_VAGUE_1:
            raise ValueError(f"critère hors vague 1 : {self.critere!r}")
        if self.est_non_applicable():
            return self  # N/A : pas de déterminations ni de signaux exigés
        # Validator dur : un score sans signaux cités est rejeté.
        if not self.signal_ids_cites:
            raise ValueError(
                "signal_ids_cites vide sans flag donnees_insuffisantes : rejet"
            )
        derive_score(self.critere, self.determinations)  # lève si invalide
        return self

    def est_non_applicable(self) -> bool:
        return "donnees_insuffisantes" in self.flags

    def score_derive(self) -> tuple[float, int | None]:
        """Score faisant foi (avant garde-fous aval)."""
        return derive_score(self.critere, self.determinations)


# --------------------------------------------------------------------------- #
# Enveloppes d'artefacts + golden set.
# --------------------------------------------------------------------------- #
class _BatchArtifact(BaseModel):
    run_id: str
    agent: str
    genere_at: datetime
    version_prompt: str | None = None


class SignalBatchArtifact(_BatchArtifact):
    items: list[SignalArtifact]


class DebunkageBatchArtifact(_BatchArtifact):
    items: list[DebunkageArtifact]


class EvaluationBatchArtifact(_BatchArtifact):
    items: list[EvaluationOutput]


class GoldenEntry(BaseModel):
    """Une notation humaine de référence pour (média, critère)."""

    media_domaine: str
    critere: str
    statut: str  # evaluee | non_applicable | revue_requise
    score: float | None = None
    niveau: int | None = None
    commentaire: str | None = None

    @model_validator(mode="after")
    def _coherence(self) -> GoldenEntry:
        if self.critere not in CRITERES_VAGUE_1:
            raise ValueError(f"critère hors vague 1 : {self.critere!r}")
        if self.statut == "evaluee":
            if self.score is None:
                raise ValueError("statut evaluee exige un score")
            if self.critere in CRITERES_NIVEAUX and self.niveau not in (0, 1, 2):
                raise ValueError(f"{self.critere}: niveau 0|1|2 requis dans le gold")
        return self


class GoldenSet(BaseModel):
    """`docs/media-eval/golden/gold_v0.json` — notation Laurin."""

    version_methodo: str = VERSION_METHODO
    notateur: str = "humain:laurin"
    note_at: datetime | None = None
    entries: list[GoldenEntry]
