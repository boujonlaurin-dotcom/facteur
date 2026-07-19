#!/usr/bin/env python3
"""Contrats Pydantic + grilles versionnées du pipeline media-eval (C1–C11).

Source de vérité **codée en dur** des règles mécaniques de la méthodo
(cf. docs/media-eval/) : barèmes, registre des types de signaux, dérivation du
score depuis les `determinations` de l'évaluateur, dérivation du poids
émetteur des débunkages. Rien de tout cela n'est confié aux prompts — même
philosophie que `derive_reliability` dans `scripts/source_eval_schema.py`.

**Versionnement (v1.2 ↔ v1.3).** La version est portée **par run**
(`media_eval_runs.version_methodo`) : le batch 1 (v1.2, 11 critères, axes
50/30/20) et le batch 2 (v1.3, 10 critères tous à niveaux, axes 60/20/20)
coexistent sans réécriture. Le code neuf résout `grille(run.version_methodo)` ;
les alias « plats » du module (``BAREMES``, ``CRITERES_VAGUE_1``…) restent en
**v1.2** pour la relecture du batch 1 et la compat des tests existants.

Les artefacts JSON produits par les agents (voie B + évaluateurs) sont validés
ici AVANT toute écriture DB (`ingest_artifacts.py`, `ingest_evaluations.py`) :
un artefact invalide est rejeté en bloc, rien n'est écrit. Chaque artefact
porte sa ``version_methodo`` (défaut v1.2) : la validation applique la grille
correspondante.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime

from pydantic import BaseModel, Field, field_validator, model_validator

from app.models.media_eval import (
    GraviteDebunkage,
    PoidsEmetteur,
    StatutSignal,
    SuiteDonnee,
)

# Défaut back-compat : les artefacts et le code sans version explicite relisent
# le batch 1 (run v1.2). Les nouveaux runs sont créés en v1.3 (create_run).
VERSION_METHODO = "v1.2"
VERSION_METHODO_COURANTE = "v1.3"

# --------------------------------------------------------------------------- #
# Grilles versionnées (méthodo §4, verbatim) — jamais dans les prompts.
# --------------------------------------------------------------------------- #

# ---- v1.2 : 11 critères, axes 50/30/20 -------------------------------------- #
_BAREMES_V12: dict[str, int] = {
    "C1": 20, "C2": 15, "C3": 10, "C4": 5, "C5": 10,
    "C6": 6, "C7": 4, "C8": 4, "C9": 10, "C10": 10, "C11": 6,
}  # total 100
_CRITERES_VAGUE_1_V12 = ("C1", "C5", "C7", "C8", "C9", "C11")  # 54 pts
_CRITERES_NIVEAUX_V12 = ("C9", "C11")  # échelles à niveaux (le reste = continu)
_NIVEAU_SCORES_V12: dict[str, dict[int, int]] = {
    "C9": {0: 0, 1: 5, 2: 10},
    "C11": {0: 0, 1: 3, 2: 6},
}
# Échelle de scores possibles par critère : plafonnement « palier inférieur »
# du garde-fou de corroboration.
_PALIERS_V12: dict[str, tuple[int, ...]] = {
    "C1": (0, 5, 10, 15, 20),
    "C5": (0, 5, 10),
    "C7": (0, 2, 4),
    "C8": (0, 2, 4),
    "C9": (0, 5, 10),
    "C11": (0, 3, 6),
}
_TYPE_SIGNAUX_V12: dict[str, tuple[str, ...]] = {
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
_FRAICHEUR_V12 = 730
_AXES_V12: dict[str, tuple[str, ...]] = {
    "axe1_rigueur": ("C1", "C2", "C3", "C4"),
    "axe2_transparence": ("C5", "C6", "C7", "C8"),
    "axe3_independance": ("C9", "C10", "C11"),
}
_DOUBLE_EVAL_V12 = ("C9", "C11")

# ---- v1.3 : 10 critères, axes 60/20/20, tous à niveaux ---------------------- #
_BAREMES_V13: dict[str, int] = {
    "C1": 20, "C2": 15, "C3": 10, "C4": 5, "C5": 10,
    "C6": 10, "C7": 6, "C8": 4, "C9": 10, "C10": 10,
}  # total 100 (axes 60/20/20)
# Vague 1 v1.3 = critères évaluables hors corpus d'articles (= re-mapping du
# batch 1). Les critères sur corpus (C2/C3/C4/C5 diversité/C7) arrivent au
# batch 2 (collecte d'échantillons §5.4) avec leur registre TYPE_SIGNAUX.
_CRITERES_VAGUE_1_V13 = ("C1", "C6", "C8", "C9", "C10")
_CRITERES_NIVEAUX_V13 = (
    "C1", "C2", "C3", "C4", "C5", "C6", "C7", "C8", "C9", "C10",
)
_NIVEAU_SCORES_V13: dict[str, dict[int, int]] = {
    "C1": {0: 0, 1: 5, 2: 10, 3: 15, 4: 20},
    "C2": {0: 0, 1: 3, 2: 7, 3: 11, 4: 15},
    "C3": {0: 0, 1: 1, 2: 4, 3: 7, 4: 10},
    "C4": {0: 0, 1: 1, 2: 3, 3: 5},
    "C5": {0: 0, 1: 5, 2: 10},
    "C6": {0: 0, 1: 1, 2: 4, 3: 7, 4: 10},
    "C7": {0: 0, 1: 2, 2: 4, 3: 6},
    "C8": {0: 0, 1: 1, 2: 3, 3: 4},
    "C9": {0: 0, 1: 5, 2: 10},
    "C10": {0: 0, 1: 5, 2: 10},
}
_PALIERS_V13: dict[str, tuple[int, ...]] = {
    c: tuple(sorted(set(scores.values()))) for c, scores in _NIVEAU_SCORES_V13.items()
}
# Registre des signaux : batch 1 v1.3 (structurels + tierces). Le C9 fusionné
# hérite des signaux ex-C8 (engagement déontologique) ET ex-C11 (positionnement).
_TYPE_SIGNAUX_V13: dict[str, tuple[str, ...]] = {
    "C1": ("debunkage", "sanction_arcom", "condamnation_justice", "avis_cdjm"),
    "C6": (
        "mentions_legales",
        "identification_proprietaire",
        "structure_actionnariat",
        "enregistrement_cppap",
        "transparence_financement",
    ),
    "C8": (
        "marquage_contenu_sponsorise",
        "regie_pub_identifiee",
        "politique_publicitaire",
    ),
    "C9": (
        "charte_deontologique",
        "adhesion_cdjm",
        "certification_jti",
        "reference_charte_externe",
        "manifeste_positionnement",
        "ligne_editoriale_publiee",
        "auto_description_orientation",
        "rubriques_opinion_identifiees",
    ),
    "C10": (
        "charte_independance",
        "societe_journalistes",
        "independance_capital",
        "intervention_actionnaire",
        "statuts_redaction",
    ),
}
_FRAICHEUR_V13 = 1095  # 36 mois (décision PO 18/07/2026)
_AXES_V13: dict[str, tuple[str, ...]] = {
    "axe1_rigueur": ("C1", "C2", "C3", "C4", "C5"),  # 60
    "axe2_transparence": ("C6", "C7", "C8"),  # 20
    "axe3_independance": ("C9", "C10"),  # 20
}
_DOUBLE_EVAL_V13 = ("C5", "C9", "C10")  # critères à 3 niveaux (décision PO)

# Lettres A–E sur le score renormalisé /100 (méthodo §4.4.1) — communes.
LETTRES: list[tuple[int, str]] = [(85, "A"), (70, "B"), (55, "C"), (40, "D"), (0, "E")]


@dataclass(frozen=True)
class Grille:
    """Règles mécaniques d'une version de méthodo (barèmes, échelles, axes)."""

    version: str
    baremes: dict[str, int]
    criteres_vague_1: tuple[str, ...]
    criteres_niveaux: tuple[str, ...]
    niveau_scores: dict[str, dict[int, int]]
    paliers: dict[str, tuple[int, ...]]
    type_signaux: dict[str, tuple[str, ...]]
    fraicheur_max_jours: int
    axes: dict[str, tuple[str, ...]]
    criteres_double_eval: tuple[str, ...]
    lettres: list[tuple[int, str]]

    @property
    def types_evenementiels(self) -> frozenset[str]:
        """Types « événementiels » (fenêtre de fraîcheur) — les signaux C1."""
        return frozenset(self.type_signaux["C1"])


GRILLES: dict[str, Grille] = {
    "v1.2": Grille(
        version="v1.2",
        baremes=_BAREMES_V12,
        criteres_vague_1=_CRITERES_VAGUE_1_V12,
        criteres_niveaux=_CRITERES_NIVEAUX_V12,
        niveau_scores=_NIVEAU_SCORES_V12,
        paliers=_PALIERS_V12,
        type_signaux=_TYPE_SIGNAUX_V12,
        fraicheur_max_jours=_FRAICHEUR_V12,
        axes=_AXES_V12,
        criteres_double_eval=_DOUBLE_EVAL_V12,
        lettres=LETTRES,
    ),
    "v1.3": Grille(
        version="v1.3",
        baremes=_BAREMES_V13,
        criteres_vague_1=_CRITERES_VAGUE_1_V13,
        criteres_niveaux=_CRITERES_NIVEAUX_V13,
        niveau_scores=_NIVEAU_SCORES_V13,
        paliers=_PALIERS_V13,
        type_signaux=_TYPE_SIGNAUX_V13,
        fraicheur_max_jours=_FRAICHEUR_V13,
        axes=_AXES_V13,
        criteres_double_eval=_DOUBLE_EVAL_V13,
        lettres=LETTRES,
    ),
}
for _g in GRILLES.values():
    assert sum(_g.baremes.values()) == 100, f"barèmes {_g.version} ≠ 100"


def grille(version: str) -> Grille:
    """Grille mécanique d'une version de méthodo (lève si inconnue)."""
    try:
        return GRILLES[version]
    except KeyError:
        raise ValueError(
            f"version methodo inconnue: {version!r} (connues: {sorted(GRILLES)})"
        ) from None


# --------------------------------------------------------------------------- #
# Alias « plats » = v1.2 (relecture du batch 1 + compat des tests). Ne pas
# ajouter de nouvel usage plat : le code neuf passe par `grille(version)`.
# --------------------------------------------------------------------------- #
BAREMES = _BAREMES_V12
CRITERES_VAGUE_1 = _CRITERES_VAGUE_1_V12
CRITERES_NIVEAUX = _CRITERES_NIVEAUX_V12
NIVEAU_SCORES = _NIVEAU_SCORES_V12
PALIERS = _PALIERS_V12
TYPE_SIGNAUX = _TYPE_SIGNAUX_V12
TYPES_EVENEMENTIELS = GRILLES["v1.2"].types_evenementiels
FRAICHEUR_MAX_JOURS = _FRAICHEUR_V12

assert sum(BAREMES.values()) == 100

# Garde-fous mécaniques (architecture §6) — communs aux grilles.
FALLBACK_C1_MIN_DEBUNKAGES = 3
CORROBORATION_MIN_SOURCES = 2

# Pondération des émetteurs de débunkages (amendement v1.2 C1, §5.2.1 v1.3) —
# dérivée par code depuis l'émetteur normalisé, jamais choisie par l'agent. Les
# rubriques de fact-checking de médias concurrents directs = poids réduit
# (conflit d'intérêts potentiel documenté). Émetteur inconnu -> `faible`.
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

# Déterminations énumérables des critères continus v1.2 (rubriques v1.2).
C1_PROFILS: dict[str, int] = {
    "aucun_signal_negatif": 20,
    "problemes_mineurs_corriges": 15,
    "problemes_mixtes": 10,
    "problemes_significatifs": 5,
    "fabrication_ou_refus_non_corrige": 0,
}
# Notation méthodo v1.2 §5.3-É2 (continue) : plein / 50 % / 0.
PROFILS_SIGNAUX: tuple[str, ...] = ("positifs_majoritaires", "mixtes", "negatifs")


def derive_score(
    critere: str, determinations: dict, version: str = VERSION_METHODO
) -> tuple[float, int | None]:
    """Score faisant foi, dérivé par code depuis les `determinations`.

    Retourne ``(score, niveau)`` — ``niveau`` renseigné pour les critères à
    niveaux (v1.3 : tous ; v1.2 : C9/C11), ``None`` pour les critères continus
    v1.2 (C1/C5/C7/C8). Lève ``ValueError`` si les déterminations ne respectent
    pas la rubrique de la ``version`` (mêmes règles que ``EvaluationOutput``).
    """
    g = grille(version)
    if critere in g.criteres_niveaux:
        niveau = determinations.get("niveau")
        scores = g.niveau_scores[critere]
        if niveau not in scores:
            raise ValueError(
                f"{critere}: niveau invalide {niveau!r} (attendu {sorted(scores)})"
            )
        return float(scores[niveau]), niveau
    # Critères continus v1.2 (profils). En v1.3 tous les critères sont à niveaux,
    # donc ces branches ne sont jamais atteintes.
    if critere == "C1":
        profil = determinations.get("profil_veracite")
        if profil not in C1_PROFILS:
            raise ValueError(f"C1: profil_veracite invalide {profil!r}")
        return float(C1_PROFILS[profil]), None
    if critere in ("C5", "C7", "C8"):
        profil = determinations.get("profil_signaux")
        if profil not in PROFILS_SIGNAUX:
            raise ValueError(f"{critere}: profil_signaux invalide {profil!r}")
        plein = float(g.baremes[critere])
        return {"positifs_majoritaires": plein, "mixtes": plein / 2, "negatifs": 0.0}[
            profil
        ], None
    raise ValueError(f"critère hors vague 1 ({version}) : {critere!r}")


def palier_inferieur(
    critere: str, score: float, version: str = VERSION_METHODO
) -> float:
    """Palier immédiatement inférieur au score (garde-fou corroboration)."""
    paliers = grille(version).paliers[critere]
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
    version_methodo: str = VERSION_METHODO
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
        registre = grille(self.version_methodo).type_signaux.get(self.critere)
        if registre is None:
            raise ValueError(
                f"critère hors registre {self.version_methodo} : {self.critere!r}"
            )
        if self.type_signal not in registre:
            raise ValueError(
                f"type_signal {self.type_signal!r} hors registre {self.critere} "
                f"({self.version_methodo})"
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
    débunkage + signal C1 (contrat évaluateur uniforme). Le registre C1 est
    identique en v1.2 et v1.3 : cet artefact est indépendant de la version.
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
        if v not in _TYPE_SIGNAUX_V12["C1"]:
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
    version_methodo: str = VERSION_METHODO
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
        g = grille(self.version_methodo)
        if self.critere not in g.criteres_vague_1:
            raise ValueError(
                f"critère hors vague 1 ({self.version_methodo}) : {self.critere!r}"
            )
        if self.est_non_applicable():
            return self  # N/A : pas de déterminations ni de signaux exigés
        # Validator dur : un score sans signaux cités est rejeté.
        if not self.signal_ids_cites:
            raise ValueError(
                "signal_ids_cites vide sans flag donnees_insuffisantes : rejet"
            )
        derive_score(self.critere, self.determinations, self.version_methodo)
        return self

    def est_non_applicable(self) -> bool:
        return "donnees_insuffisantes" in self.flags

    def score_derive(self) -> tuple[float, int | None]:
        """Score faisant foi (avant garde-fous aval)."""
        return derive_score(self.critere, self.determinations, self.version_methodo)


# --------------------------------------------------------------------------- #
# Enveloppes d'artefacts + golden set.
# --------------------------------------------------------------------------- #
def _propager_version(data: object) -> object:
    """Stampe ``version_methodo`` du batch dans chaque item qui ne la porte pas."""
    if isinstance(data, dict):
        v = data.get("version_methodo") or VERSION_METHODO
        items = data.get("items")
        if isinstance(items, list):
            for it in items:
                if isinstance(it, dict) and "version_methodo" not in it:
                    it["version_methodo"] = v
    return data


class _BatchArtifact(BaseModel):
    run_id: str
    agent: str
    genere_at: datetime
    version_prompt: str | None = None


class SignalBatchArtifact(_BatchArtifact):
    version_methodo: str = VERSION_METHODO
    items: list[SignalArtifact]

    @model_validator(mode="before")
    @classmethod
    def _stamp_version(cls, data: object) -> object:
        return _propager_version(data)


class DebunkageBatchArtifact(_BatchArtifact):
    items: list[DebunkageArtifact]


class EvaluationBatchArtifact(_BatchArtifact):
    version_methodo: str = VERSION_METHODO
    items: list[EvaluationOutput]

    @model_validator(mode="before")
    @classmethod
    def _stamp_version(cls, data: object) -> object:
        return _propager_version(data)


class GoldenEntry(BaseModel):
    """Une notation humaine de référence pour (média, critère)."""

    media_domaine: str
    critere: str
    version_methodo: str = VERSION_METHODO
    statut: str  # evaluee | non_applicable | revue_requise
    score: float | None = None
    niveau: int | None = None
    commentaire: str | None = None

    @model_validator(mode="after")
    def _coherence(self) -> GoldenEntry:
        g = grille(self.version_methodo)
        if self.critere not in g.criteres_vague_1:
            raise ValueError(
                f"critère hors vague 1 ({self.version_methodo}) : {self.critere!r}"
            )
        if self.statut == "evaluee":
            if self.score is None:
                raise ValueError("statut evaluee exige un score")
            if self.critere in g.criteres_niveaux:
                scores = g.niveau_scores[self.critere]
                if self.niveau not in scores:
                    raise ValueError(
                        f"{self.critere}: niveau attendu {sorted(scores)} dans le gold"
                    )
        return self


class GoldenSet(BaseModel):
    """`docs/media-eval/golden/gold_v*.json` — notation Laurin."""

    version_methodo: str = VERSION_METHODO
    notateur: str = "humain:laurin"
    note_at: datetime | None = None
    entries: list[GoldenEntry]

    @model_validator(mode="before")
    @classmethod
    def _stamp_version(cls, data: object) -> object:
        if isinstance(data, dict):
            v = data.get("version_methodo") or VERSION_METHODO
            for it in data.get("entries", []) or []:
                if isinstance(it, dict) and "version_methodo" not in it:
                    it["version_methodo"] = v
        return data
