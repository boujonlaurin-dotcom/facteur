"""Tests purs des contrats Pydantic media-eval (scripts/media_eval/schemas.py).

Couvre : rejet d'un score sans signal_ids ; type_signal hors registre ;
niveau requis C9/C11 ; table de cas `derive_score` ; dérivation du poids
émetteur ; publie_at manquant sur un débunkage.
"""

from __future__ import annotations

import pytest
from pydantic import ValidationError

from scripts.media_eval.schemas import (
    BAREMES,
    CRITERES_VAGUE_1,
    GRILLES,
    DebunkageArtifact,
    EvaluationBatchArtifact,
    EvaluationOutput,
    GoldenEntry,
    SignalArtifact,
    derive_poids_emetteur,
    derive_score,
    grille,
    palier_inferieur,
)


def make_eval(**kw) -> dict:
    base = {
        "media_domaine": "cnews.fr",
        "critere": "C5",
        "determinations": {"profil_signaux": "positifs_majoritaires"},
        "justification": "Mentions légales complètes [signal:a].",
        "signal_ids_cites": ["3f0a5b1e-0000-0000-0000-000000000001"],
        "flags": [],
    }
    base.update(kw)
    return base


class TestEvaluationOutput:
    def test_score_sans_signal_ids_rejete(self):
        with pytest.raises(ValidationError, match="signal_ids_cites vide"):
            EvaluationOutput.model_validate(make_eval(signal_ids_cites=[]))

    def test_na_sans_signal_ids_accepte(self):
        ev = EvaluationOutput.model_validate(
            make_eval(
                signal_ids_cites=[],
                determinations={},
                flags=["donnees_insuffisantes"],
            )
        )
        assert ev.est_non_applicable()

    def test_flag_hors_contrat_rejete(self):
        with pytest.raises(ValidationError, match="flags hors contrat"):
            EvaluationOutput.model_validate(make_eval(flags=["score_bonus"]))

    def test_critere_hors_vague_1_rejete(self):
        with pytest.raises(ValidationError, match="hors vague 1"):
            EvaluationOutput.model_validate(make_eval(critere="C2"))

    def test_niveau_requis_c9(self):
        with pytest.raises(ValidationError, match="niveau invalide"):
            EvaluationOutput.model_validate(
                make_eval(critere="C9", determinations={"profil_signaux": "mixtes"})
            )

    def test_niveau_hors_bornes_c11(self):
        with pytest.raises(ValidationError, match="niveau invalide"):
            EvaluationOutput.model_validate(
                make_eval(critere="C11", determinations={"niveau": 3})
            )

    def test_determination_valide_c9(self):
        ev = EvaluationOutput.model_validate(
            make_eval(critere="C9", determinations={"niveau": 1})
        )
        assert ev.score_derive() == (5.0, 1)


class TestDeriveScore:
    @pytest.mark.parametrize(
        ("critere", "determinations", "attendu"),
        [
            ("C1", {"profil_veracite": "aucun_signal_negatif"}, (20.0, None)),
            ("C1", {"profil_veracite": "problemes_mineurs_corriges"}, (15.0, None)),
            ("C1", {"profil_veracite": "problemes_mixtes"}, (10.0, None)),
            ("C1", {"profil_veracite": "problemes_significatifs"}, (5.0, None)),
            (
                "C1",
                {"profil_veracite": "fabrication_ou_refus_non_corrige"},
                (0.0, None),
            ),
            ("C5", {"profil_signaux": "positifs_majoritaires"}, (10.0, None)),
            ("C5", {"profil_signaux": "mixtes"}, (5.0, None)),
            ("C7", {"profil_signaux": "mixtes"}, (2.0, None)),
            ("C7", {"profil_signaux": "negatifs"}, (0.0, None)),
            ("C8", {"profil_signaux": "positifs_majoritaires"}, (4.0, None)),
            ("C9", {"niveau": 0}, (0.0, 0)),
            ("C9", {"niveau": 2}, (10.0, 2)),
            ("C11", {"niveau": 1}, (3.0, 1)),
            ("C11", {"niveau": 2}, (6.0, 2)),
        ],
    )
    def test_table(self, critere, determinations, attendu):
        assert derive_score(critere, determinations) == attendu

    def test_profil_c1_invalide(self):
        with pytest.raises(ValueError, match="profil_veracite invalide"):
            derive_score("C1", {"profil_veracite": "correct"})

    def test_critere_vague_2_refuse(self):
        with pytest.raises(ValueError, match="hors vague 1"):
            derive_score("C10", {"niveau": 1})

    def test_vague_1_couverte(self):
        # Chaque critère vague 1 a une dérivation définie.
        exemples = {
            "C1": {"profil_veracite": "problemes_mixtes"},
            "C5": {"profil_signaux": "mixtes"},
            "C7": {"profil_signaux": "mixtes"},
            "C8": {"profil_signaux": "mixtes"},
            "C9": {"niveau": 1},
            "C11": {"niveau": 1},
        }
        for critere in CRITERES_VAGUE_1:
            score, _ = derive_score(critere, exemples[critere])
            assert 0 <= score <= BAREMES[critere]


class TestPalierInferieur:
    @pytest.mark.parametrize(
        ("critere", "score", "attendu"),
        [
            ("C1", 20, 15.0),
            ("C5", 10, 5.0),
            ("C7", 4, 2.0),
            ("C9", 10, 5.0),
            ("C11", 6, 3.0),
            ("C1", 0, 0.0),
        ],
    )
    def test_paliers(self, critere, score, attendu):
        assert palier_inferieur(critere, score) == attendu


class TestPoidsEmetteur:
    def test_derivation(self):
        assert derive_poids_emetteur("cdjm") == "fort"
        assert derive_poids_emetteur("ARCOM") == "fort"
        assert derive_poids_emetteur("afp_factuel") == "moyen"
        assert derive_poids_emetteur("blog-inconnu") == "faible"


class TestSignalArtifact:
    def make(self, **kw) -> dict:
        base = {
            "media_domaine": "reporterre.net",
            "critere": "C11",
            "type_signal": "manifeste_positionnement",
            "statut": "present",
            "source_urls": ["https://reporterre.net/notre-projet"],
        }
        base.update(kw)
        return base

    def test_type_signal_hors_registre(self):
        with pytest.raises(ValidationError, match="hors registre"):
            SignalArtifact.model_validate(self.make(type_signal="charte_independance"))

    def test_present_sans_source_rejete(self):
        with pytest.raises(ValidationError, match="source_urls vide"):
            SignalArtifact.model_validate(self.make(source_urls=[]))

    def test_absent_verifie_exige_sources_consultees(self):
        with pytest.raises(ValidationError, match="sources_consultees"):
            SignalArtifact.model_validate(
                self.make(statut="absent_verifie", source_urls=[])
            )
        ok = SignalArtifact.model_validate(
            self.make(
                statut="absent_verifie",
                source_urls=[],
                sources_consultees=["https://reporterre.net/plan-du-site"],
            )
        )
        assert ok.statut == "absent_verifie"


_UUID = "3f0a5b1e-0000-0000-0000-000000000001"


class TestGrilleV13:
    """Grille v1.3 : 10 critères tous à niveaux, axes 60/20/20, fenêtre 36 mois."""

    def test_registre_deux_grilles(self):
        assert set(GRILLES) == {"v1.2", "v1.3"}
        g = grille("v1.3")
        assert sum(g.baremes.values()) == 100
        assert g.criteres_vague_1 == ("C1", "C6", "C8", "C9", "C10")
        assert g.fraicheur_max_jours == 1095
        assert g.criteres_double_eval == ("C5", "C9", "C10")

    def test_version_inconnue_leve(self):
        with pytest.raises(ValueError, match="version methodo inconnue"):
            grille("v9.9")

    @pytest.mark.parametrize(
        ("critere", "niveau", "attendu"),
        [
            ("C1", 4, (20.0, 4)),
            ("C1", 0, (0.0, 0)),
            ("C2", 3, (11.0, 3)),
            ("C3", 2, (4.0, 2)),
            ("C4", 3, (5.0, 3)),
            ("C5", 2, (10.0, 2)),
            ("C6", 2, (4.0, 2)),
            ("C7", 3, (6.0, 3)),
            ("C8", 1, (1.0, 1)),
            ("C9", 1, (5.0, 1)),
            ("C10", 2, (10.0, 2)),
        ],
    )
    def test_derive_score_v13(self, critere, niveau, attendu):
        assert derive_score(critere, {"niveau": niveau}, "v1.3") == attendu

    def test_derive_score_v13_niveau_hors_bornes(self):
        # C4 est à 4 niveaux (0-3) : niveau 4 n'existe pas.
        with pytest.raises(ValueError, match="niveau invalide"):
            derive_score("C4", {"niveau": 4}, "v1.3")

    def test_evaluation_output_v13(self):
        ev = EvaluationOutput.model_validate(
            {
                "media_domaine": "cnews.fr",
                "critere": "C1",
                "version_methodo": "v1.3",
                "determinations": {"niveau": 3},
                "justification": "Signaux faibles corrigés [signal:a].",
                "signal_ids_cites": [_UUID],
            }
        )
        assert ev.score_derive() == (15.0, 3)

    def test_evaluation_output_v13_hors_vague_1(self):
        # C2 (sourçage) est sur corpus : hors vague 1 v1.3 (batch 2).
        with pytest.raises(ValidationError, match="hors vague 1"):
            EvaluationOutput.model_validate(
                {
                    "media_domaine": "cnews.fr",
                    "critere": "C2",
                    "version_methodo": "v1.3",
                    "determinations": {"niveau": 2},
                    "justification": "x [signal:a].",
                    "signal_ids_cites": [_UUID],
                }
            )

    def test_signal_artifact_v13_fusion_c9(self):
        # Le C9 fusionné hérite des signaux ex-C8 (engagement) ET ex-C11 (position).
        sig = SignalArtifact.model_validate(
            {
                "media_domaine": "cnews.fr",
                "critere": "C9",
                "version_methodo": "v1.3",
                "type_signal": "manifeste_positionnement",
                "statut": "present",
                "source_urls": ["https://cnews.fr/charte"],
            }
        )
        assert sig.critere == "C9"

    def test_signal_artifact_v13_type_hors_registre(self):
        # certification_jti appartient à C9 en v1.3, pas à C6.
        with pytest.raises(ValidationError, match="hors registre"):
            SignalArtifact.model_validate(
                {
                    "media_domaine": "cnews.fr",
                    "critere": "C6",
                    "version_methodo": "v1.3",
                    "type_signal": "certification_jti",
                    "statut": "present",
                    "source_urls": ["https://cnews.fr/x"],
                }
            )

    def test_batch_stampe_version_dans_items(self):
        batch = EvaluationBatchArtifact.model_validate(
            {
                "run_id": "r",
                "agent": "agent:media-eval-evaluateur@v1-a",
                "genere_at": "2026-07-18T00:00:00Z",
                "version_methodo": "v1.3",
                "items": [
                    {
                        "media_domaine": "cnews.fr",
                        "critere": "C10",
                        "determinations": {"niveau": 2},
                        "justification": "Gouvernance incluant la rédaction [signal:a].",
                        "signal_ids_cites": [_UUID],
                    }
                ],
            }
        )
        assert batch.items[0].version_methodo == "v1.3"
        assert batch.items[0].score_derive() == (10.0, 2)

    def test_golden_entry_v13_niveau_hors_bornes(self):
        # C9 v1.3 = 3 niveaux (0-2) : niveau 3 rejeté dans le gold.
        with pytest.raises(ValidationError, match="niveau attendu"):
            GoldenEntry.model_validate(
                {
                    "media_domaine": "cnews.fr",
                    "critere": "C9",
                    "version_methodo": "v1.3",
                    "statut": "evaluee",
                    "score": 5.0,
                    "niveau": 3,
                }
            )


class TestDebunkageArtifact:
    def make(self, **kw) -> dict:
        base = {
            "media_domaine": "cnews.fr",
            "url_debunkage": "https://cdjm.org/avis/26-014",
            "emetteur": "cdjm",
            "gravite": "mineure",
            "suite_donnee": "aucune",
            "publie_at": "2026-02-03",
            "source_urls": ["https://cdjm.org/avis/26-014"],
        }
        base.update(kw)
        return base

    def test_publie_at_manquant_rejete(self):
        artefact = self.make()
        del artefact["publie_at"]
        with pytest.raises(ValidationError):
            DebunkageArtifact.model_validate(artefact)

    def test_poids_derive_ignore_agent(self):
        # Même si l'agent fournissait un poids, seul le dérivé fait foi.
        deb = DebunkageArtifact.model_validate(self.make())
        assert deb.poids_emetteur() == "fort"

    def test_gravite_hors_enum(self):
        with pytest.raises(ValidationError, match="gravite hors enum"):
            DebunkageArtifact.model_validate(self.make(gravite="catastrophique"))
