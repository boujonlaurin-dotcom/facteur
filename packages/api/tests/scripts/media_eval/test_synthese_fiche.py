"""Tests purs de la synthèse de fiche (scripts/media_eval/synthese_fiche.py).

Couvre : renormalisation 0/1/3 N/A ; bornes des lettres (84.9 → B, 85 → A) ;
matrice de confiance ; cas Reporterre simulé (C1 N/A → max 34).
"""

from __future__ import annotations

from scripts.media_eval.synthese_fiche import compute_fiche, lettre_pour


def make_eval(critere: str, score: float | None, statut: str = "evaluee", **kw) -> dict:
    base = {
        "critere": critere,
        "statut": statut,
        "score": score,
        "niveau": None,
        "flags": [],
        "evaluateur": "agent:media-eval-evaluateur@v1",
    }
    base.update(kw)
    return base


def evals_completes(**overrides) -> list[dict]:
    """6 critères vague 1 évalués au max (54 pts)."""
    scores = {"C1": 20.0, "C5": 10.0, "C7": 4.0, "C8": 4.0, "C9": 10.0, "C11": 6.0}
    return [overrides.get(c, make_eval(c, s)) for c, s in scores.items()]


class TestLettres:
    def test_bornes(self):
        assert lettre_pour(85.0) == "A"
        assert lettre_pour(84.9) == "B"
        assert lettre_pour(70.0) == "B"
        assert lettre_pour(69.9) == "C"
        assert lettre_pour(55.0) == "C"
        assert lettre_pour(40.0) == "D"
        assert lettre_pour(39.9) == "E"
        assert lettre_pour(0.0) == "E"


class TestRenormalisation:
    def test_zero_na_max_54(self):
        fiche = compute_fiche(evals_completes())
        assert fiche["score_max_applicable"] == 54.0
        assert fiche["score_brut"] == 54.0
        assert fiche["score_renormalise"] == 100.0
        assert fiche["lettre"] == "A"
        assert fiche["confiance"] == "haute"

    def test_un_na_reporterre_max_34(self):
        # Cas Reporterre : C1 N/A (donnees_insuffisantes) → renormalise sur 34.
        fiche = compute_fiche(
            evals_completes(
                C1=make_eval(
                    "C1",
                    None,
                    statut="non_applicable",
                    flags=["donnees_insuffisantes"],
                )
            )
        )
        assert fiche["score_max_applicable"] == 34.0
        assert fiche["criteres_na"] == ["C1"]
        assert fiche["score_renormalise"] == 100.0
        assert fiche["confiance"] == "moyenne"  # 1 N/A -> plus haute

    def test_trois_na_confiance_basse(self):
        fiche = compute_fiche(
            evals_completes(
                C1=make_eval("C1", None, statut="non_applicable"),
                C7=make_eval("C7", None, statut="non_applicable"),
                C8=make_eval("C8", None, statut="non_applicable"),
            )
        )
        assert fiche["score_max_applicable"] == 26.0
        assert fiche["confiance"] == "basse"

    def test_score_partiel(self):
        fiche = compute_fiche(
            evals_completes(
                C1=make_eval("C1", 10.0),
                C9=make_eval("C9", 5.0, niveau=1),
            )
        )
        assert fiche["score_brut"] == 39.0
        assert fiche["score_renormalise"] == 72.2  # 39/54
        assert fiche["lettre"] == "B"

    def test_aucune_evaluee(self):
        fiche = compute_fiche([make_eval("C1", None, statut="non_applicable")])
        assert fiche["score_max_applicable"] == 0.0
        assert fiche["score_renormalise"] == 0.0
        assert fiche["lettre"] == "E"


class TestConfiance:
    def test_signaux_contradictoires_moyenne(self):
        fiche = compute_fiche(
            evals_completes(C5=make_eval("C5", 5.0, flags=["signaux_contradictoires"]))
        )
        assert fiche["confiance"] == "moyenne"

    def test_corroboration_insuffisante_moyenne(self):
        fiche = compute_fiche(
            evals_completes(
                C8=make_eval("C8", 2.0, flags=["corroboration_insuffisante"])
            )
        )
        assert fiche["confiance"] == "moyenne"

    def test_revue_humaine_requise_basse(self):
        fiche = compute_fiche(
            evals_completes(C9=make_eval("C9", 5.0, flags=["revue_humaine_requise"]))
        )
        assert fiche["confiance"] == "basse"

    def test_critere_revue_requise_basse_et_exclu_du_max(self):
        fiche = compute_fiche(
            evals_completes(
                C7=make_eval("C7", None, statut="revue_requise", flags=["bloque_acces"])
            )
        )
        assert fiche["criteres_revue_requise"] == ["C7"]
        assert fiche["score_max_applicable"] == 50.0
        assert fiche["confiance"] == "basse"


class TestPreferenceEvaluateur:
    def test_code_prime_sur_agent(self):
        fiche = compute_fiche(
            evals_completes() + [make_eval("C8", 4.0, evaluateur="code:jti_shortcut")]
        )
        assert fiche["detail"]["C8"]["evaluateur"] == "code:jti_shortcut"
