"""Tests du benchmark d'accord vs golden set (evaluate_golden_agreement.py).

Mini-fixtures : 6 paires couvrant accord continu (|Δ| ≤ 20 % du barème),
désaccord de niveau (C9), désaccord N/A-vs-score, et accords exacts.
"""

from __future__ import annotations

from pathlib import Path

from scripts.media_eval.evaluate_golden_agreement import evaluate, render_md
from scripts.media_eval.schemas import GoldenSet

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
