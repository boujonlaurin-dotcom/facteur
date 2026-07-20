"""Tests du benchmark d'accord vs golden set (evaluate_golden_agreement.py).

Mini-fixtures : 6 paires couvrant accord continu (|Δ| ≤ 20 % du barème),
désaccord de niveau (C9), désaccord N/A-vs-score, et accords exacts.
"""

from __future__ import annotations

from pathlib import Path

from scripts.media_eval.evaluate_golden_agreement import (
    _paire_accord,
    evaluate,
    render_md,
)
from scripts.media_eval.export_evaluations import accord_inter_evaluateurs
from scripts.media_eval.schemas import GoldenEntry, GoldenSet

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures" / "media_eval"


def _charger() -> tuple[GoldenSet, GoldenSet]:
    gold = GoldenSet.model_validate_json((FIXTURES / "gold_mini.json").read_text())
    generated = GoldenSet.model_validate_json(
        (FIXTURES / "generated_mini.json").read_text()
    )
    return gold, generated


class TestEvaluate:
    def test_metriques(self):
        gold, generated = _charger()
        report = evaluate(gold, generated)

        assert report["n"] == 6
        # Accords : C1 cnews (Δ4 ≤ 4), C5 cnews, C11 cnews, C9 reporterre.
        assert report["accord_global"] == round(4 / 6, 3)
        assert report["par_media"] == {"cnews.fr": "3/4", "reporterre.net": "1/2"}
        # Reporterre C1 : gold N/A vs généré scoré -> désaccord critique.
        assert report["na_vs_score"] == 1
        # MAE sur les paires scorées des deux côtés : [4, 0, 5, 0, 0] -> 1.8.
        assert report["mae_scores"] == 1.8

    def test_desaccords_tries_na_dabord(self):
        gold, generated = _charger()
        report = evaluate(gold, generated)
        types = [d["type_desaccord"] for d in report["desaccords"]]
        assert types == ["na_vs_score", "niveau"]

    def test_niveau_exact_exige_c9(self):
        # C9 cnews : même si Δ score (5) serait toléré en continu, le
        # niveau 0 vs 1 est un désaccord (accord exact exigé).
        gold, generated = _charger()
        report = evaluate(gold, generated)
        c9 = next(
            d
            for d in report["desaccords"]
            if d["critere"] == "C9" and d["media"] == "cnews.fr"
        )
        assert c9["type_desaccord"] == "niveau"

    def test_gold_vide(self):
        gold, generated = _charger()
        report = evaluate(GoldenSet(entries=[]), generated)
        assert report["n"] == 0

    def test_render_md(self):
        gold, generated = _charger()
        md = render_md(evaluate(gold, generated))
        assert "na_vs_score" in md
        assert "reporterre.net" in md


def _ev(critere, evaluateur, *, statut="evaluee", score=None, niveau=None):
    return {
        "media_domaine": "cnews.fr",
        "critere": critere,
        "statut": statut,
        "score": score,
        "niveau": niveau,
        "evaluateur": evaluateur,
    }


class TestAccordInterEvaluateurs:
    def test_accord_et_desaccord(self):
        evals = [
            # C9 : deux évaluateurs, accord (niveau 1).
            _ev("C9", "agent:e@v1-a", score=5, niveau=1),
            _ev("C9", "agent:e@v1-b", score=5, niveau=1),
            # C5 : deux évaluateurs, désaccord (niveau 2 vs 1).
            _ev("C5", "agent:e@v1-a", score=10, niveau=2),
            _ev("C5", "agent:e@v1-b", score=5, niveau=1),
            # C6 : un seul évaluateur → hors du décompte inter-évaluateurs.
            _ev("C6", "agent:e@v1", score=4, niveau=2),
        ]
        rep = accord_inter_evaluateurs(evals)
        assert rep["n"] == 2  # C9 + C5 seulement
        assert rep["accords"] == 1
        assert rep["accord_inter"] == 0.5
        assert [d["critere"] for d in rep["desaccords"]] == ["C5"]
        assert rep["desaccords"][0]["verdicts"] == {
            "agent:e@v1-a": "niveau 2",
            "agent:e@v1-b": "niveau 1",
        }

    def test_aucune_double_eval(self):
        rep = accord_inter_evaluateurs([_ev("C9", "agent:e@v1", score=5, niveau=1)])
        assert rep["n"] == 0
        assert rep["accord_inter"] is None


class TestVersionV13:
    def _pair(self, gold_niv, gen_niv):
        g = GoldenEntry(
            media_domaine="cnews.fr",
            critere="C2",
            version_methodo="v1.3",
            statut="evaluee",
            score=float(gold_niv),
            niveau=gold_niv,
        )
        gen = GoldenEntry(
            media_domaine="cnews.fr",
            critere="C2",
            version_methodo="v1.3",
            statut="evaluee",
            score=float(gen_niv),
            niveau=gen_niv,
        )
        return _paire_accord(g, gen)

    def test_c2_v13_est_a_niveaux(self):
        # C2 est continu en v1.2 mais à niveaux en v1.3 : l'accord est exact
        # sur le niveau, pas une tolérance de 20 %.
        assert self._pair(2, 2)["accord"] is True
        r = self._pair(2, 3)
        assert r["accord"] is False
        assert r["type_desaccord"] == "niveau"
