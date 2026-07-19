"""Tests de l'export d'évaluations (export_evaluations.py).

Couvre : transformation en GoldenSet ; inclusion du raccourci code:jti_shortcut
et exclusion des préfixes non demandés ; erreur explicite sur (média, critère)
dupliqué.
"""

from __future__ import annotations

import pytest

from scripts.media_eval.export_evaluations import evaluations_to_goldenset


def _ev(
    media,
    critere,
    statut="evaluee",
    score=None,
    niveau=None,
    evaluateur="agent:media-eval-evaluateur@v1",
):
    return {
        "media_domaine": media,
        "critere": critere,
        "statut": statut,
        "score": score,
        "niveau": niveau,
        "evaluateur": evaluateur,
    }


class TestEvaluationsToGoldenset:
    def test_nominal(self):
        evals = [
            _ev("cnews.fr", "C5", score=10),
            _ev("cnews.fr", "C8", score=4, evaluateur="code:jti_shortcut"),
            _ev("cnews.fr", "C9", score=5, niveau=1),
        ]
        gs = evaluations_to_goldenset(evals)
        assert len(gs.entries) == 3
        # Le raccourci code: est bien inclus.
        assert any(e.critere == "C8" for e in gs.entries)

    def test_filtre_prefixes(self):
        evals = [
            _ev("cnews.fr", "C5", score=10),
            _ev("cnews.fr", "C1", statut="non_applicable", evaluateur="humain:laurin"),
        ]
        gs = evaluations_to_goldenset(evals, prefixes=("agent:", "code:"))
        assert len(gs.entries) == 1
        assert gs.entries[0].critere == "C5"

    def test_doublon_media_critere_leve(self):
        evals = [
            _ev("cnews.fr", "C5", score=10),
            _ev("cnews.fr", "C5", score=5, evaluateur="code:autre"),
        ]
        with pytest.raises(ValueError, match="deux évaluations"):
            evaluations_to_goldenset(evals)

    def test_na_score_null(self):
        gs = evaluations_to_goldenset(
            [_ev("reporterre.net", "C1", statut="non_applicable")]
        )
        assert gs.entries[0].statut == "non_applicable"
        assert gs.entries[0].score is None
