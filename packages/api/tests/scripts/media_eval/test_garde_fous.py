"""Tests purs des garde-fous mécaniques (scripts/media_eval/garde_fous.py).

Couvre : fraîcheur 729/731 j ; fallback C1 à 2 vs 3 débunkages ; corroboration
1 source → plafonné + flag ; raccourci JTI ; `bloque_acces` jamais 0.
"""

from __future__ import annotations

from datetime import date, timedelta

from scripts.media_eval.garde_fous import (
    appliquer_corroboration,
    compter_sources_independantes,
    detecter_jti_valide,
    est_frais,
    fallback_c1_requis,
    filtrer_fraicheur,
    statut_evaluation,
)
from scripts.media_eval.schemas import FLAG_CORROBORATION

AUJOURD_HUI = date(2026, 7, 8)


def signal_evenementiel(jours: int, **kw) -> dict:
    base = {
        "type_signal": "debunkage",
        "statut": "present",
        "valeur": {"publie_at": (AUJOURD_HUI - timedelta(days=jours)).isoformat()},
        "source_urls": ["https://cdjm.org/avis/1"],
    }
    base.update(kw)
    return base


class TestFraicheur:
    def test_729_jours_frais(self):
        assert est_frais(signal_evenementiel(729), AUJOURD_HUI)

    def test_730_jours_limite_incluse(self):
        assert est_frais(signal_evenementiel(730), AUJOURD_HUI)

    def test_731_jours_exclu(self):
        assert not est_frais(signal_evenementiel(731), AUJOURD_HUI)

    def test_structurel_sans_limite(self):
        charte = {
            "type_signal": "charte_independance",
            "statut": "present",
            "valeur": {"publie_at": "2008-01-01"},
        }
        assert est_frais(charte, AUJOURD_HUI)

    def test_evenementiel_sans_date_exclu(self):
        assert not est_frais(
            {"type_signal": "sanction_arcom", "valeur": {}}, AUJOURD_HUI
        )

    def test_filtre(self):
        frais, exclus = filtrer_fraicheur(
            [signal_evenementiel(10), signal_evenementiel(800)], AUJOURD_HUI
        )
        assert len(frais) == 1 and len(exclus) == 1


class TestFallbackC1:
    def test_2_debunkages_declenche(self):
        assert fallback_c1_requis(2)

    def test_3_debunkages_ne_declenche_pas(self):
        assert not fallback_c1_requis(3)


class TestCorroboration:
    def test_score_plein_1_source_plafonne(self):
        cites = [
            {"source_urls": ["https://cnews.fr/a", "https://www.cnews.fr/b"]}
        ]  # www. déduit -> 1 seul domaine
        score, flags = appliquer_corroboration("C5", 10.0, cites)
        assert score == 5.0
        assert flags == [FLAG_CORROBORATION]

    def test_score_plein_2_sources_intact(self):
        cites = [
            {"source_urls": ["https://cnews.fr/mentions"]},
            {"source_urls": ["https://pappers.fr/entreprise/sesi"]},
        ]
        score, flags = appliquer_corroboration("C5", 10.0, cites)
        assert score == 10.0 and flags == []

    def test_score_partiel_jamais_plafonne(self):
        cites = [{"source_urls": ["https://cnews.fr/mentions"]}]
        score, flags = appliquer_corroboration("C5", 5.0, cites)
        assert score == 5.0 and flags == []

    def test_compteur_domaines(self):
        assert (
            compter_sources_independantes(
                [
                    {"source_urls": ["https://www.arcom.fr/d1", "https://arcom.fr/d2"]},
                    {"source_urls": ["https://conseil-etat.fr/x"]},
                ]
            )
            == 2
        )


class TestRaccourciJTI:
    def test_certification_valide_detectee(self):
        signal = {
            "id": "abc",
            "type_signal": "certification_jti",
            "statut": "present",
            "valeur": {"en_cours_de_validite": True},
        }
        assert detecter_jti_valide([signal]) is signal

    def test_certification_expiree_ignoree(self):
        assert (
            detecter_jti_valide(
                [
                    {
                        "type_signal": "certification_jti",
                        "statut": "present",
                        "valeur": {"en_cours_de_validite": False},
                    }
                ]
            )
            is None
        )

    def test_absence_ignoree(self):
        assert (
            detecter_jti_valide(
                [
                    {
                        "type_signal": "certification_jti",
                        "statut": "absent_verifie",
                        "valeur": {"en_cours_de_validite": True},
                    },
                    {"type_signal": "charte_deontologique", "statut": "present"},
                ]
            )
            is None
        )


class TestStatutEvaluation:
    def test_donnees_insuffisantes_na(self):
        assert statut_evaluation(["donnees_insuffisantes"], []) == "non_applicable"

    def test_flag_bloque_acces_revue(self):
        assert statut_evaluation(["bloque_acces"], []) == "revue_requise"

    def test_signaux_tous_bloques_revue_jamais_zero(self):
        cites = [{"statut": "bloque_acces"}, {"statut": "bloque_acces"}]
        assert statut_evaluation([], cites) == "revue_requise"

    def test_signaux_mixtes_evaluee(self):
        cites = [{"statut": "bloque_acces"}, {"statut": "present"}]
        assert statut_evaluation([], cites) == "evaluee"
