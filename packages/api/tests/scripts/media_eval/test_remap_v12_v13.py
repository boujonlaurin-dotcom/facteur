"""Tests du re-mapping gold v1.2 → v1.3 (scripts/media_eval/remap_v12_v13.py).

Pur (fichiers/fonctions, aucune DB) : logique de bracket des niveaux, conservation
des N/A / a_noter, fusion ex-C8 + ex-C11 → C9, ordre stable, et validation du
résultat contre la grille v1.3.
"""

from __future__ import annotations

from scripts.media_eval.remap_v12_v13 import (
    DECISIONS_PO,
    _bracket_niveaux,
    appliquer_decisions_po,
    remap_fusion,
    remap_simple,
    remapper,
)
from scripts.media_eval.schemas import GoldenSet, grille


def _gold_v0() -> dict:
    return {
        "version_methodo": "v1.2",
        "notateur": "humain:laurin",
        "entries": [
            {"media_domaine": "cnews.fr", "critere": "C1", "statut": "non_applicable",
             "score": None, "commentaire": "fallback"},
            {"media_domaine": "cnews.fr", "critere": "C5", "statut": "evaluee",
             "score": 5, "commentaire": "mixtes"},
            {"media_domaine": "cnews.fr", "critere": "C7", "statut": "evaluee",
             "score": 2, "commentaire": "mixtes"},
            {"media_domaine": "cnews.fr", "critere": "C8", "statut": "evaluee",
             "score": 0, "commentaire": "negatifs"},
            {"media_domaine": "cnews.fr", "critere": "C9", "statut": "evaluee",
             "score": 0, "niveau": 0, "commentaire": "absent"},
            {"media_domaine": "cnews.fr", "critere": "C11", "statut": "evaluee",
             "score": 3, "niveau": 1, "commentaire": "partiel"},
        ],
    }


class TestBracket:
    def test_score_sur_palier_exact(self):
        # C6 v1.3 : 0/1/4/7/10 → score 7 = niveau 3.
        scores = grille("v1.3").niveau_scores["C6"]
        assert _bracket_niveaux(7, scores) == ("exact", [3])

    def test_score_hors_palier_encadre(self):
        scores = grille("v1.3").niveau_scores["C6"]
        assert _bracket_niveaux(5, scores) == ("revue", [2, 3])

    def test_c8_deux_sur_quatre(self):
        # C8 v1.3 : 0/1/3/4 → score 2 encadré par niveaux 1 (1) et 2 (3).
        scores = grille("v1.3").niveau_scores["C8"]
        assert _bracket_niveaux(2, scores) == ("revue", [1, 2])


class TestRemapSimple:
    def test_na_conserve(self):
        e = {"media_domaine": "x", "critere": "C1", "statut": "non_applicable",
             "score": None, "commentaire": "c"}
        out = remap_simple(e, "C1")
        assert out["statut"] == "non_applicable"
        assert out["critere"] == "C1"
        assert out["origine_v12"][0]["critere"] == "C1"

    def test_niveau_identique_conserve(self):
        # C9 v1.2 niveau 0 → C10 v1.3 niveau 0, échelle identique.
        e = {"media_domaine": "x", "critere": "C9", "statut": "evaluee",
             "score": 0, "niveau": 0, "commentaire": "c"}
        out = remap_simple(e, "C10")
        assert (out["statut"], out["niveau"], out["score"]) == ("evaluee", 0, 0.0)
        assert out["regle_remap"] == "niveaux_identiques"

    def test_continue_hors_echelle_revue(self):
        e = {"media_domaine": "x", "critere": "C5", "statut": "evaluee",
             "score": 5, "commentaire": "c"}
        out = remap_simple(e, "C6")
        assert out["statut"] == "revue_requise"
        assert out["candidats_niveau"] == [2, 3]
        assert out["candidats_score"] == [4, 7]


class TestRemapFusion:
    def test_fusion_evaluee_revue(self):
        sources = [
            {"media_domaine": "x", "critere": "C8", "statut": "evaluee", "score": 0,
             "commentaire": "neg"},
            {"media_domaine": "x", "critere": "C11", "statut": "evaluee", "score": 3,
             "niveau": 1, "commentaire": "part"},
        ]
        out = remap_fusion("x", sources)
        assert out["critere"] == "C9"
        assert out["statut"] == "revue_requise"
        assert out["candidats_niveau"] == [0, 1]
        assert {o["critere"] for o in out["origine_v12"]} == {"C8", "C11"}

    def test_fusion_a_noter_aveugle(self):
        sources = [
            {"media_domaine": "x", "critere": "C8", "statut": "a_noter",
             "score": None, "commentaire": "n"},
            {"media_domaine": "x", "critere": "C11", "statut": "a_noter",
             "score": None, "commentaire": "n"},
        ]
        out = remap_fusion("x", sources)
        assert out["statut"] == "a_noter"


class TestRemapperComplet:
    def test_ordre_et_criteres(self):
        entries = remapper(_gold_v0())
        criteres = [e["critere"] for e in entries]
        assert criteres == ["C1", "C6", "C8", "C9", "C10"]

    def test_resultat_valide_grille_v13(self):
        entries = remapper(_gold_v0())
        gold = {"version_methodo": "v1.3", "notateur": "humain:laurin",
                "entries": entries}
        # Ne lève pas : critères en vague 1 v1.3, niveaux bornés.
        GoldenSet.model_validate(gold)


class TestDecisionsPO:
    def test_tranche_revue_requise_en_evaluee(self):
        # Les 3 cas CNEWS revue_requise deviennent evaluee au niveau PO retenu.
        entries = appliquer_decisions_po(remapper(_gold_v0()))
        par_critere = {e["critere"]: e for e in entries
                       if e["media_domaine"] == "cnews.fr"}
        assert (par_critere["C6"]["statut"], par_critere["C6"]["niveau"],
                par_critere["C6"]["score"]) == ("evaluee", 2, 4.0)
        assert (par_critere["C8"]["statut"], par_critere["C8"]["niveau"],
                par_critere["C8"]["score"]) == ("evaluee", 2, 3.0)
        assert (par_critere["C9"]["statut"], par_critere["C9"]["niveau"],
                par_critere["C9"]["score"]) == ("evaluee", 0, 0.0)

    def test_score_derive_de_la_grille_v13(self):
        # Le score figé correspond au palier v1.3 du niveau retenu.
        g13 = grille("v1.3")
        for (_, critere), decision in DECISIONS_PO.items():
            attendu = g13.niveau_scores[critere][decision["niveau"]]
            assert "score" not in decision or decision["score"] == attendu

    def test_provenance_et_candidats_conserves(self):
        entries = appliquer_decisions_po(remapper(_gold_v0()))
        c9 = next(e for e in entries
                  if e["media_domaine"] == "cnews.fr" and e["critere"] == "C9")
        assert {o["critere"] for o in c9["origine_v12"]} == {"C8", "C11"}
        assert c9["candidats_niveau"] == [0, 1]
        assert c9["decision_po"]["motif"]
        assert "decision_po" in c9["regle_remap"]

    def test_entree_sans_decision_inchangee(self):
        # Une entrée hors DECISIONS_PO (ex. C1 non_applicable) traverse inchangée.
        avant = remapper(_gold_v0())
        c1_avant = next(e for e in avant if e["critere"] == "C1")["statut"]
        apres = appliquer_decisions_po(remapper(_gold_v0()))
        c1_apres = next(e for e in apres if e["critere"] == "C1")["statut"]
        assert c1_avant == c1_apres == "non_applicable"

    def test_resultat_reste_valide_grille_v13(self):
        entries = appliquer_decisions_po(remapper(_gold_v0()))
        gold = {"version_methodo": "v1.3", "notateur": "humain:laurin",
                "entries": entries}
        GoldenSet.model_validate(gold)
