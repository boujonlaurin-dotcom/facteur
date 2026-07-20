"""Tests des rendus purs + preuve D4 du rapport pilote (rapport_pilote.py)."""

from __future__ import annotations

from datetime import UTC, datetime

from scripts.media_eval.rapport_pilote import (
    NOTE_ABSENT,
    NOTE_BLOQUE,
    NOTE_NA,
    NOTE_PARTIEL,
    NOTE_RICHE,
    _accord_par_media,
    _verifier_d4,
    construire_metrics,
    evaluer_proprete_donnees,
    render_html,
    tableau_signaux,
    verdict_v0,
)
from scripts.media_eval.synthese_fiche import compute_fiche


def _signal(media, critere, statut, voie="code", *, sources=None, consultees=None):
    return {
        "media": media,
        "critere": critere,
        "type_signal": "mentions_legales",
        "statut": statut,
        "voie": voie,
        "citation": "extrait" if statut == "present" else None,
        "source_urls": sources or [],
        "sources_consultees": consultees or [],
    }


class TestRendusPurs:
    def test_tableau_signaux_comptage(self):
        signaux = [
            {
                "media": "cnews.fr",
                "critere": "C5",
                "type_signal": "mentions_legales",
                "statut": "present",
                "voie": "code",
            },
            {
                "media": "cnews.fr",
                "critere": "C5",
                "type_signal": "structure_actionnariat",
                "statut": "present",
                "voie": "code",
            },
            {
                "media": "cnews.fr",
                "critere": "C1",
                "type_signal": "sanction_arcom",
                "statut": "present",
                "voie": "code",
            },
        ]
        rendu = tableau_signaux(signaux)
        assert "cnews.fr" in rendu
        assert "| 2 " in rendu  # 2 signaux C5 code present

    def test_tableau_signaux_vide(self):
        assert tableau_signaux([]) == "(aucun signal)"

    def test_accord_par_media_parse(self):
        report = {"par_media": {"cnews.fr": "5/6", "reporterre.net": "3/4"}}
        assert _accord_par_media(report) == {"cnews.fr": 5, "reporterre.net": 3}


class TestVerdictV0:
    def _metrics(self, **kw):
        base = {
            "n_evaluations": 12,
            "evaluations_valides": True,
            "accord_par_media": {"cnews.fr": 5, "reporterre.net": 4},
            "reporterre": {"c1_statut": "non_applicable", "max_applicable": 34.0},
            "zero_ecriture_agent": True,
        }
        base.update(kw)
        return base

    def test_tous_pass(self):
        crit = verdict_v0(self._metrics())
        assert all(c["pass"] for c in crit)

    def test_accord_insuffisant_fail(self):
        crit = verdict_v0(
            self._metrics(accord_par_media={"cnews.fr": 3, "reporterre.net": 4})
        )
        accord = next(c for c in crit if c["critere"].startswith("2."))
        assert accord["pass"] is False

    def test_reporterre_max_incorrect_fail(self):
        crit = verdict_v0(
            self._metrics(
                reporterre={"c1_statut": "non_applicable", "max_applicable": 54.0}
            )
        )
        rep = next(c for c in crit if c["critere"].startswith("3."))
        assert rep["pass"] is False


class TestConstruireMetrics:
    def test_reporterre_c1_na_et_max(self):
        evals = [
            {
                "media_domaine": "reporterre.net",
                "critere": "C1",
                "statut": "non_applicable",
                "evaluateur": "agent:x",
            },
            {
                "media_domaine": "reporterre.net",
                "critere": "C9",
                "statut": "evaluee",
                "evaluateur": "agent:x",
            },
        ]
        fiches = {"reporterre.net": {"score_max_applicable": 34.0}}
        report = {"par_media": {"reporterre.net": "5/6"}}
        metrics = construire_metrics(evals, report, fiches)
        assert metrics["reporterre"]["c1_statut"] == "non_applicable"
        assert metrics["reporterre"]["max_applicable"] == 34.0


class TestD4:
    def test_gold_avant_ok(self):
        note = datetime(2026, 7, 10, 9, 0, tzinfo=UTC)
        evalue = datetime(2026, 7, 10, 12, 0, tzinfo=UTC)
        assert _verifier_d4(note, evalue)["ok"] is True

    def test_gold_apres_warning(self):
        note = datetime(2026, 7, 10, 13, 0, tzinfo=UTC)
        evalue = datetime(2026, 7, 10, 12, 0, tzinfo=UTC)
        d4 = _verifier_d4(note, evalue)
        assert d4["ok"] is False
        assert "WARNING" in d4["message"]

    def test_gold_note_at_absent(self):
        assert _verifier_d4(None, datetime(2026, 7, 10, tzinfo=UTC))["ok"] is False


class TestPropreteDonnees:
    def _note(self, proprete, media, critere):
        cell = next(
            c
            for c in proprete["cellules"]
            if c["media"] == media and c["critere"] == critere
        )
        return cell

    def test_riche_corrobore_deux_domaines(self):
        signaux = [
            _signal(
                "cnews.fr",
                "C5",
                "present",
                sources=["https://cnews.fr/mentions", "https://pappers.fr/x"],
            )
        ]
        prop = evaluer_proprete_donnees(signaux, [], {}, "v1.2")
        cell = self._note(prop, "cnews.fr", "C5")
        assert cell["note"] == NOTE_RICHE
        assert cell["corrobore"] is True
        assert cell["n_sources"] == 2

    def test_present_une_seule_source_est_partiel(self):
        # Deux URLs mais un seul domaine → non corroboré → partiel.
        signaux = [
            _signal(
                "cnews.fr",
                "C7",
                "present",
                sources=["https://cnews.fr/a", "https://www.cnews.fr/b"],
            )
        ]
        prop = evaluer_proprete_donnees(signaux, [], {}, "v1.2")
        cell = self._note(prop, "cnews.fr", "C7")
        assert cell["note"] == NOTE_PARTIEL
        assert cell["corrobore"] is False
        assert cell["n_sources"] == 1

    def test_bloque_est_un_trou_absent_est_propre(self):
        signaux = [
            _signal("cnews.fr", "C1", "bloque_acces"),
            _signal(
                "reporterre.net",
                "C8",
                "absent_verifie",
                voie="agent",
                consultees=["https://reporterre.net/charte", "https://cdjm.org"],
            ),
        ]
        prop = evaluer_proprete_donnees(signaux, [], {}, "v1.2")
        assert self._note(prop, "cnews.fr", "C1")["note"] == NOTE_BLOQUE
        assert self._note(prop, "reporterre.net", "C8")["note"] == NOTE_ABSENT
        # La distinction se lit dans le rollup : bloque compté comme trou.
        assert prop["par_media"]["cnews.fr"]["n_bloque"] == 1
        assert prop["par_media"]["reporterre.net"]["n_bloque"] == 0

    def test_eval_non_applicable_prime_sur_signaux(self):
        signaux = [_signal("reporterre.net", "C1", "bloque_acces")]
        evals = [
            {
                "media_domaine": "reporterre.net",
                "critere": "C1",
                "statut": "non_applicable",
            }
        ]
        prop = evaluer_proprete_donnees(signaux, evals, {}, "v1.2")
        assert self._note(prop, "reporterre.net", "C1")["note"] == NOTE_NA

    def test_cellule_sans_signal_ni_eval_ignoree(self):
        prop = evaluer_proprete_donnees(
            [_signal("cnews.fr", "C5", "present", sources=["https://cnews.fr/x"])],
            [],
            {},
            "v1.2",
        )
        criteres = {c["critere"] for c in prop["cellules"]}
        assert criteres == {"C5"}  # les autres critères ne sont pas inventés

    def test_rollup_global_agrege(self):
        signaux = [
            _signal(
                "cnews.fr",
                "C5",
                "present",
                sources=["https://cnews.fr/x", "https://pappers.fr/y"],
            ),
            _signal("cnews.fr", "C1", "bloque_acces"),
        ]
        prop = evaluer_proprete_donnees(signaux, [], {}, "v1.2")
        assert prop["global"]["n_signaux"] == 2
        assert prop["global"]["n_corrobore"] == 1
        assert prop["global"]["pct_corrobore"] == 1.0  # 1 corroboré / 1 avec donnée


def _rapport_data_synthetique():
    """Construit un RapportData réaliste (2 médias, N/A, bloque, désaccord)."""
    signaux = [
        _signal(
            "cnews.fr",
            "C5",
            "present",
            sources=["https://cnews.fr/mentions", "https://pappers.fr/x"],
        ),
        _signal(
            "cnews.fr", "C7", "present", voie="agent", sources=["https://cnews.fr/pub"]
        ),
        _signal("cnews.fr", "C1", "bloque_acces"),
        _signal(
            "reporterre.net",
            "C8",
            "absent_verifie",
            voie="agent",
            consultees=["https://reporterre.net/charte"],
        ),
    ]
    evals = [
        {
            "media_domaine": "cnews.fr",
            "critere": "C5",
            "statut": "evaluee",
            "score": 10.0,
            "niveau": None,
            "flags": [],
            "evaluateur": "agent:x",
        },
        {
            "media_domaine": "cnews.fr",
            "critere": "C7",
            "statut": "evaluee",
            "score": 2.0,
            "niveau": None,
            "flags": [],
            "evaluateur": "agent:x",
        },
        {
            "media_domaine": "reporterre.net",
            "critere": "C1",
            "statut": "non_applicable",
            "score": None,
            "niveau": None,
            "flags": ["donnees_insuffisantes"],
            "evaluateur": "agent:x",
        },
        {
            "media_domaine": "reporterre.net",
            "critere": "C8",
            "statut": "evaluee",
            "score": 4.0,
            "niveau": None,
            "flags": [],
            "evaluateur": "agent:x",
        },
    ]
    fiches = {}
    par_media = {}
    for e in evals:
        par_media.setdefault(e["media_domaine"], []).append(e)
    for media, evs in par_media.items():
        fiches[media] = compute_fiche(evs, "v1.2")
    accord = {
        "n": 4,
        "accord_global": 0.75,
        "par_media": {"cnews.fr": "2/2", "reporterre.net": "1/2"},
        "na_vs_score": 1,
        "mae_scores": 1.5,
        "desaccords": [
            {
                "media": "reporterre.net",
                "critere": "C8",
                "gold_statut": "evaluee",
                "gen_statut": "non_applicable",
                "gold_score": 4.0,
                "gen_score": None,
                "gold_niveau": None,
                "gen_niveau": None,
                "type_desaccord": "na_vs_score",
                "delta": None,
                "accord": False,
            },
        ],
    }
    return {
        "run": {
            "run_id": "pilote-2026-07",
            "version_methodo": "v1.2",
            "date_reference": "2026-07-08",
            "perimetre": {"medias": ["cnews.fr", "reporterre.net"]},
        },
        "rubrics_sha": dict.fromkeys(("C1", "C5", "C7", "C8", "C9", "C11"), "0" * 64),
        "d4": {"ok": True, "message": "OK — gold noté avant les évaluations."},
        "signaux": signaux,
        "evaluations": evals,
        "garde_fous": {"bloque_acces": "oui (signaux bloqués présents)"},
        "accord_report": accord,
        "fiches": fiches,
        "verdict": [
            {"critere": "1. Artefacts valides", "pass": True, "preuve": "4 évals"},
            {"critere": "2. Accord ≥ 4/6", "pass": False, "preuve": "reporterre: 1/6"},
            {"critere": "3. Reporterre C1 = N/A", "pass": True, "preuve": "C1 N/A"},
            {"critere": "4. Zéro écriture agent", "pass": True, "preuve": "ok"},
        ],
    }


class TestRenderHtml:
    def _html(self):
        data = _rapport_data_synthetique()
        prop = evaluer_proprete_donnees(
            data["signaux"], data["evaluations"], data["fiches"], "v1.2"
        )
        return render_html(data, prop)

    def test_document_autonome_valide(self):
        page = self._html()
        assert page.startswith("<!DOCTYPE html>")
        assert page.rstrip().endswith("</html>")
        assert "<style>" in page  # CSS inline, single-file
        assert page.count("<html") == 1

    def test_lentille_proprete_ouvre_le_rapport(self):
        page = self._html()
        i_prop = page.index('id="proprete"')
        i_accord = page.index('id="accord"')
        assert i_prop < i_accord  # propreté avant l'accord (ordre confirmé)
        assert "trou d'accès" in page
        assert "Absence confirmée" in page

    def test_marqueurs_cles_presents(self):
        page = self._html()
        # Verdict global (ici FAIL car accord insuffisant).
        assert "V0 non validé" in page
        # Badges de voie.
        assert "b-code" in page and "b-agent" in page
        # Preuve D4.
        assert "Preuve D4" in page
        assert "gold noté avant les évaluations" in page
        # Notes de complétude + accord.
        assert "Riche" in page and "Bloqué" in page
        assert "Accord global" in page

    def test_desaccord_na_vs_score_surligne(self):
        page = self._html()
        assert "na_vs_score" in page
        assert "row-warn" in page  # ligne surlignée

    def test_voie_humain_rend_classe_css_valide(self):
        # voie 'humain' (fr) → classe design system 'd-human'/'b-human' (en).
        data = _rapport_data_synthetique()
        data["signaux"].append(
            _signal(
                "cnews.fr",
                "C9",
                "present",
                voie="humain",
                sources=["https://cnews.fr/x", "https://sdj.fr/y"],
            )
        )
        prop = evaluer_proprete_donnees(
            data["signaux"], data["evaluations"], data["fiches"], "v1.2"
        )
        page = render_html(data, prop)
        assert "d-human" in page and "b-human" in page
        assert "d-humain" not in page  # pas de classe inexistante

    def test_verdict_valide_si_tous_pass(self):
        data = _rapport_data_synthetique()
        for c in data["verdict"]:
            c["pass"] = True
        prop = evaluer_proprete_donnees(
            data["signaux"], data["evaluations"], data["fiches"], "v1.2"
        )
        page = render_html(data, prop)
        assert "V0 VALIDÉ" in page
