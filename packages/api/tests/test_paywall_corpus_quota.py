"""Règle de quota du corpus paywall — la partie qui tourne sans les fixtures.

`quota_status()` décide quand une source du corpus est en défaut. C'est la seule
logique du harnais que la CI peut exercer : `labels.json` est versionné, alors
que `html/` et `rss/` ne le sont pas. Elle est testée ici sur des manifestes
synthétiques, parce que le vrai corpus n'a pas de raison de contenir en
permanence les cas limites qu'elle doit tenir.

Les trois cas ci-dessous sont ceux qui faisaient échouer le harnais à tort :
étiquetage en cours, média entièrement gratuit, source jamais collectée.
"""

import yaml

from scripts.build_paywall_corpus import MANIFEST_PATH, quota_status, summarize_quota


def _manifest(*sources: dict) -> dict:
    return {
        "min_paid_per_source": 3,
        "min_free_per_source": 3,
        "sources": list(sources),
    }


def _labels(slug: str, paid: int, free: int, unlabeled: int = 0) -> dict[str, dict]:
    rows = {}
    for index, label in enumerate(["paid"] * paid + ["free"] * free + [None] * unlabeled):
        rows[f"{slug}-{index:02d}"] = {"source": slug, "label": label, "url": ""}
    return rows


def test_source_en_cours_detiquetage_nest_pas_en_defaut():
    """L'étiquetage se fait média par média, sur plusieurs sessions.

    Juger une source à moitié étiquetée ferait échouer la suite pendant tout ce
    travail — c'était le défaut qui rendait le premier lot de labels inmergeable.
    """
    manifest = _manifest({"slug": "novethic", "group": "false_negative"})
    status = quota_status(manifest, _labels("novethic", paid=1, free=1, unlabeled=8))

    assert status["novethic"]["complete"] is False
    assert status["novethic"]["unlabeled"] == 8


def test_source_terminee_sous_quota_est_en_defaut():
    """Étiquetage fini et quota raté : c'est le corpus qu'il faut élargir."""
    manifest = _manifest({"slug": "novethic", "group": "false_negative"})
    status = quota_status(manifest, _labels("novethic", paid=9, free=1))

    assert status["novethic"]["complete"] is True
    assert status["novethic"]["meets_quota"] is False


def test_source_terminee_au_quota_est_conforme():
    manifest = _manifest({"slug": "novethic", "group": "false_negative"})
    status = quota_status(manifest, _labels("novethic", paid=3, free=3))

    assert status["novethic"]["meets_quota"] is True


def test_media_entierement_gratuit_est_dispense_du_quota_de_payants():
    """Exiger 3 payants de Bon Pote demanderait ce que le média ne publie pas."""
    manifest = _manifest(
        {"slug": "bonpote", "group": "false_positive_trap", "expects_paid": False}
    )
    status = quota_status(manifest, _labels("bonpote", paid=0, free=10))

    assert status["bonpote"]["meets_quota"] is True


def test_media_gratuit_reste_soumis_au_quota_de_gratuits():
    """La dispense ne porte que sur les payants.

    Ces sources sont le piège à faux positifs : sans articles gratuits en
    nombre, elles ne mesurent plus rien du seul critère bloquant de la refonte.
    """
    manifest = _manifest(
        {"slug": "bonpote", "group": "false_positive_trap", "expects_paid": False}
    )
    status = quota_status(manifest, _labels("bonpote", paid=0, free=2))

    assert status["bonpote"]["meets_quota"] is False


def test_source_sans_article_collecte_est_hors_quota():
    """`lesechos` et `lepoint` répondent 403 : ils sont au manifeste, hors corpus.

    Sans cette sortie, leur étiquetage vide compterait comme 0 payant / 0
    gratuit — un défaut permanent pour des sources qu'on n'a jamais pu collecter.
    """
    manifest = _manifest({"slug": "lesechos", "group": "regression_guard"})

    assert quota_status(manifest, {}) == {}


def test_expects_paid_vaut_vrai_par_defaut():
    """L'exemption doit être déclarée ; l'oublier ne doit jamais relâcher le quota."""
    manifest = _manifest({"slug": "novethic", "group": "false_negative"})
    status = quota_status(manifest, _labels("novethic", paid=0, free=10))

    assert status["novethic"]["expects_paid"] is True
    assert status["novethic"]["meets_quota"] is False


def test_summarize_quota_distingue_en_cours_et_termine():
    """Le collecteur avertit ; le message doit dire lequel des deux cas c'est."""
    manifest = _manifest(
        {"slug": "encours", "group": "false_negative"},
        {"slug": "termine", "group": "false_negative"},
    )
    labels = _labels("encours", paid=1, free=0, unlabeled=9) | _labels(
        "termine", paid=10, free=0
    )

    lignes = {ligne.split()[0]: ligne for ligne in summarize_quota(manifest, labels)}

    assert "9 à étiqueter" in lignes["encours"]
    assert "étiquetage terminé" in lignes["termine"]


def test_manifeste_reel_declare_lexemption_sur_le_groupe_piege():
    """Invariant du vrai manifeste, pas du synthétique.

    Une source `false_positive_trap` ajoutée sans `expects_paid: false` se
    retrouverait en défaut permanent dès son étiquetage terminé.
    """
    manifest = yaml.safe_load(MANIFEST_PATH.read_text(encoding="utf-8"))

    exemptees = {
        source["slug"]
        for source in manifest["sources"]
        if source.get("expects_paid", True) is False
    }
    pieges = {
        source["slug"]
        for source in manifest["sources"]
        if source["group"] == "false_positive_trap"
    }

    assert exemptees == pieges
