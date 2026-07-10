#!/usr/bin/env python3
"""Schéma Pydantic des évaluations de sources générées par LLM (Composant 1).

Validé à l'écriture (apply) ET à la lecture du benchmark. Garantit : enum
`bias_stance` valide, scores FQS dans [0,1], confiance dans [0,1], et **pas de
tiret cadratin** dans la `description` (règle PO copy user-facing — cf. mémoire
no-em-dash).

**reliability_score n'est plus choisi par le LLM** : il est **dérivé** des scores
via `derive_reliability(rigor, independence)` (rigueur dominante, ux exclu, règle
`mixed`). Cf. §2 de `sources/source_eval_rubric.md` (knobs PO). Les
**justifications par dimension** (biais/indép./rigueur/ux) + `sources_consulted`
sont des métadonnées de fact-check de l'artefact (jamais écrites en DB).
"""

from __future__ import annotations

from pydantic import BaseModel, Field, field_validator

from app.models.enums import BiasStance, ReliabilityScore

# Axe ordinal gauche -> droite pour la métrique d'adjacence du benchmark.
# `alternative`/`specialized`/`unknown` sont hors-axe (jamais "adjacents").
BIAS_AXIS: dict[str, int] = {
    "left": 0,
    "center-left": 1,
    "center": 2,
    "center-right": 3,
    "right": 4,
}

_EM_DASH = "—"  # —  (tiret cadratin)
_BANNED_DESC = (_EM_DASH, "&mdash;", "&#8212;")

_VALID_BIAS = {e.value for e in BiasStance}
_VALID_RELIABILITY = {e.value for e in ReliabilityScore}

# --------------------------------------------------------------------------- #
# Reliability dérivée (rubrique §2) — knobs PO, calibrés vs gold.
# --------------------------------------------------------------------------- #
RELIABILITY_RIGOR_WEIGHT = 0.7  # rigueur dominante
RELIABILITY_INDEP_WEIGHT = 0.3
RELIABILITY_HIGH_THRESHOLD = 0.72
RELIABILITY_MEDIUM_THRESHOLD = 0.50
MIXED_INDEP_FLOOR = 0.6  # indépendant...
MIXED_RIGOR_CEILING = 0.55  # ...mais rigueur faible / opinion-lourd


def derive_reliability(rigor: float | None, independence: float | None) -> str:
    """Dérive `reliability_score` depuis rigueur (dominante) + indépendance.

    `score_ux` est exclu. Renvoie un membre de `ReliabilityScore` (str). Si l'un
    des scores manque -> `unknown` (cohérent avec le gate de confiance qui met les
    scores à null). Règle `mixed` : indépendant mais rigueur faible / opinion-lourd.
    """
    if rigor is None or independence is None:
        return "unknown"
    if independence >= MIXED_INDEP_FLOOR and rigor < MIXED_RIGOR_CEILING:
        return "mixed"
    t = RELIABILITY_RIGOR_WEIGHT * rigor + RELIABILITY_INDEP_WEIGHT * independence
    if t >= RELIABILITY_HIGH_THRESHOLD:
        return "high"
    if t >= RELIABILITY_MEDIUM_THRESHOLD:
        return "medium"
    return "low"


class SourceEvaluation(BaseModel):
    """Une évaluation proposée pour une source (artefact relu avant apply).

    `reliability_score` est **optionnel en entrée** (legacy / artefacts pilot) :
    la valeur faisant foi est `derived_reliability()` (rubrique §2). Les 4 justifs
    + `sources_consulted` sont des métadonnées de fact-check (jamais en DB).
    """

    source_id: str
    name: str | None = None
    feed_url: str | None = None
    description: str | None = None
    bias_stance: str
    reliability_score: str | None = None
    score_independence: float | None = None
    score_rigor: float | None = None
    score_ux: float | None = None
    confidence: float = Field(ge=0.0, le=1.0)
    rationale: str | None = None
    # Fact-check (rubrique §0) — métadonnées artefact, pas écrites en DB.
    bias_rationale: str | None = None
    independence_rationale: str | None = None
    rigor_rationale: str | None = None
    ux_rationale: str | None = None
    sources_consulted: list[str] = Field(default_factory=list)

    @field_validator("bias_stance")
    @classmethod
    def _check_bias(cls, v: str) -> str:
        if v not in _VALID_BIAS:
            raise ValueError(f"bias_stance hors enum: {v!r}")
        return v

    @field_validator("reliability_score")
    @classmethod
    def _check_reliability(cls, v: str | None) -> str | None:
        if v is not None and v not in _VALID_RELIABILITY:
            raise ValueError(f"reliability_score hors enum: {v!r}")
        return v

    def derived_reliability(self) -> str:
        """Reliability faisant foi : dérivée des scores (rubrique §2)."""
        return derive_reliability(self.score_rigor, self.score_independence)

    @field_validator("score_independence", "score_rigor", "score_ux")
    @classmethod
    def _check_score(cls, v: float | None) -> float | None:
        if v is not None and not (0.0 <= v <= 1.0):
            raise ValueError(f"score FQS hors [0,1]: {v}")
        return v

    @field_validator("description")
    @classmethod
    def _no_em_dash(cls, v: str | None) -> str | None:
        if v and any(tok in v for tok in _BANNED_DESC):
            raise ValueError(
                "description contient un tiret cadratin (interdit copy user)"
            )
        return v

    def gated(self, threshold: float) -> SourceEvaluation:
        """Applique le gate de confiance : sous le seuil -> bias/reliability
        `unknown` + scores NULL, mais **description conservée**."""
        if self.confidence >= threshold:
            return self
        return self.model_copy(
            update={
                "bias_stance": "unknown",
                "reliability_score": "unknown",
                "score_independence": None,
                "score_rigor": None,
                "score_ux": None,
            }
        )


class EvaluationArtifact(BaseModel):
    """Fichier `sources/source_evaluations_llm.json` complet."""

    generated_at: str | None = None
    model: str | None = None
    evaluations: list[SourceEvaluation]
