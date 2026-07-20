"""Tests de l'export d'évaluations (export_evaluations.py).

Couvre : transformation en GoldenSet ; inclusion du raccourci code:jti_shortcut
et exclusion des préfixes non demandés ; **consensus double évaluation**
(accord conservé, désaccord → revue_requise documentée).
"""

from __future__ import annotations

from scripts.media_eval.export_evaluations import (
    evaluateurs_accordent,
    evaluations_to_goldenset,
)


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

    def test_consensus_accord_conserve(self):
        # Deux évaluateurs indépendants convergent (même niveau) → 1 entrée gardée.
        evals = [
            _ev("cnews.fr", "C9", score=5, niveau=1, evaluateur="agent:eval@v1-a"),
            _ev("cnews.fr", "C9", score=5, niveau=1, evaluateur="agent:eval@v1-b"),
        ]
        gs = evaluations_to_goldenset(evals)
        assert len(gs.entries) == 1
        e = gs.entries[0]
        assert e.statut == "evaluee"
        assert e.niveau == 1
        assert "consensus" in (e.commentaire or "")

    def test_consensus_desaccord_revue_requise(self):
        # Désaccord → revue_requise, les deux verdicts documentés (jamais moyenné).
        evals = [
            _ev("cnews.fr", "C9", score=10, niveau=2, evaluateur="agent:eval@v1-a"),
            _ev("cnews.fr", "C9", score=5, niveau=1, evaluateur="agent:eval@v1-b"),
        ]
        gs = evaluations_to_goldenset(evals)
        assert len(gs.entries) == 1
        e = gs.entries[0]
        assert e.statut == "revue_requise"
        assert e.score is None and e.niveau is None
        assert "niveau 2" in e.commentaire and "niveau 1" in e.commentaire

    def test_evaluateurs_accordent_predicat(self):
        base = _ev("cnews.fr", "C5", score=10, niveau=2)
        assert evaluateurs_accordent([base, dict(base)])
        autre = _ev("cnews.fr", "C5", score=5, niveau=1)
        assert not evaluateurs_accordent([base, autre])
        # Statuts différents = désaccord.
        na = _ev("cnews.fr", "C5", statut="non_applicable")
        assert not evaluateurs_accordent([base, na])

    def test_na_score_null(self):
        gs = evaluations_to_goldenset(
            [_ev("reporterre.net", "C1", statut="non_applicable")]
        )
        assert gs.entries[0].statut == "non_applicable"
        assert gs.entries[0].score is None
