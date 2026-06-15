"""Tests pour scripts/source_eval_schema.py (reliability dérivée + justifs).

Couvre : `derive_reliability` (high/medium/low + règle `mixed` + unknown si NULL,
précédence mixed) ; `reliability_score` optionnel en entrée ; justifs par dimension
+ `sources_consulted` optionnels et acceptés ; `derived_reliability()` cohérent.
"""

from __future__ import annotations

import pytest

from scripts.source_eval_schema import (
    SourceEvaluation,
    derive_reliability,
)

# --------------------------------------------------------------------------- #
# derive_reliability
# --------------------------------------------------------------------------- #


@pytest.mark.parametrize(
    "rigor, indep, expected",
    [
        (0.9, 0.8, "high"),  # t = 0.87
        (0.7, 0.6, "medium"),  # t = 0.67
        (0.4, 0.3, "low"),  # t = 0.37
        (0.55, 0.8, "medium"),  # rigor pile au plafond mixed (pas <0.55) -> t=0.625
    ],
)
def test_derive_thresholds(rigor, indep, expected):
    assert derive_reliability(rigor, indep) == expected


def test_derive_mixed_rule():
    # Indépendant (>=0.6) mais rigueur faible (<0.55) -> mixed.
    assert derive_reliability(0.4, 0.8) == "mixed"
    assert derive_reliability(0.5, 0.6) == "mixed"  # bornes


def test_derive_mixed_precedes_medium():
    # Sans la règle mixed, t = 0.7*0.5 + 0.3*1.0 = 0.65 -> medium ; la règle gagne.
    assert derive_reliability(0.5, 1.0) == "mixed"


def test_derive_unknown_when_score_missing():
    assert derive_reliability(None, 0.8) == "unknown"
    assert derive_reliability(0.7, None) == "unknown"
    assert derive_reliability(None, None) == "unknown"


def test_derive_high_boundary_inclusive():
    # t == 0.72 exactement -> high (seuil inclusif).
    assert derive_reliability(0.72, 0.72) == "high"


# --------------------------------------------------------------------------- #
# SourceEvaluation — champs optionnels + derived_reliability
# --------------------------------------------------------------------------- #


def test_reliability_score_optional():
    # On peut omettre reliability_score : la valeur faisant foi est dérivée.
    ev = SourceEvaluation(
        source_id="s1",
        bias_stance="center",
        score_rigor=0.9,
        score_independence=0.8,
        confidence=0.9,
    )
    assert ev.reliability_score is None
    assert ev.derived_reliability() == "high"


def test_rationales_and_sources_optional():
    ev = SourceEvaluation(source_id="s2", bias_stance="left", confidence=0.8)
    assert ev.bias_rationale is None
    assert ev.independence_rationale is None
    assert ev.rigor_rationale is None
    assert ev.ux_rationale is None
    assert ev.sources_consulted == []


def test_rationales_and_sources_accepted():
    ev = SourceEvaluation(
        source_id="s3",
        bias_stance="right",
        score_rigor=0.4,
        score_independence=0.8,
        confidence=0.85,
        bias_rationale="Ligne droitière assumée.",
        independence_rationale="Actionnaire pèse sur la rédaction.",
        rigor_rationale="Mises en demeure Arcom.",
        ux_rationale="Lecture correcte.",
        sources_consulted=["https://a.example", "https://b.example"],
    )
    assert ev.sources_consulted == ["https://a.example", "https://b.example"]
    assert ev.rigor_rationale == "Mises en demeure Arcom."
    assert ev.derived_reliability() == "mixed"  # indep 0.8, rigor 0.4


def test_derived_reliability_unknown_after_null_scores():
    ev = SourceEvaluation(source_id="s4", bias_stance="unknown", confidence=0.3)
    assert ev.derived_reliability() == "unknown"
