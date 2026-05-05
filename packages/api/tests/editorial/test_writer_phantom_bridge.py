"""Tests for `_strip_phantom_bridge` — guards against fabricated source
attributions when a subject has no `deep_article`. Regression for the
2026-04-30 digest where Mistral wrote "Next.ink explique pourquoi..." for
a subject with `deep_article: null`.
"""

from __future__ import annotations

import pytest

from app.services.editorial.writer import _strip_phantom_bridge


@pytest.mark.parametrize(
    "intro, expected",
    [
        # Real bug case from production digest 2026-04-30.
        (
            "La vulnérabilité expose des millions de serveurs. Next.ink explique"
            " pourquoi ces failles passent inaperçues pendant des années.",
            "La vulnérabilité expose des millions de serveurs.",
        ),
        # "Selon X" attribution.
        (
            "Le marché du travail se tend. Selon Le Monde, les tensions sont"
            " inédites depuis 2008.",
            "Le marché du travail se tend.",
        ),
        # "Comme l'explique X" tournure.
        (
            "Les arbitrages budgétaires s'annoncent serrés. Comme l'explique"
            " Mediapart, le compromis reste fragile.",
            "Les arbitrages budgétaires s'annoncent serrés.",
        ),
        # "Un éclairage de X" tournure.
        (
            "Le projet de loi divise. Un éclairage de Libération sur les"
            " coulisses du vote.",
            "Le projet de loi divise.",
        ),
        # "X détaille…" attribution at the start of phrase 2.
        (
            "Les négociations patinent depuis trois jours. Reuters détaille"
            " la position de chaque camp.",
            "Les négociations patinent depuis trois jours.",
        ),
    ],
)
def test_strip_phantom_bridge_truncates_attribution(intro: str, expected: str):
    cleaned, modified = _strip_phantom_bridge(intro)
    assert modified is True
    assert cleaned == expected


@pytest.mark.parametrize(
    "intro",
    [
        # No attribution, just a factual phrase 2 → leave intact.
        "31 ouvertures au premier semestre, un plus bas depuis 2016.",
        "Le mix éolien-solaire absorbe le choc gazier ; les ménages restent protégés.",
        # Empty / trivial inputs.
        "",
        "Une phrase courte.",
    ],
)
def test_strip_phantom_bridge_passthrough(intro: str):
    cleaned, modified = _strip_phantom_bridge(intro)
    assert modified is False
    assert cleaned == intro


def test_strip_phantom_bridge_handles_apostrophe_typographique():
    intro = (
        "Les hôpitaux saturent dans plusieurs régions. D’après Le Figaro, le pic"
        " devrait durer jusqu'à fin mai."
    )
    cleaned, modified = _strip_phantom_bridge(intro)
    assert modified is True
    assert cleaned == "Les hôpitaux saturent dans plusieurs régions."
