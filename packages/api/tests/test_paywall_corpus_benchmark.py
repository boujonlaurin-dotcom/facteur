"""Garde-fou anti-régression de la détection paywall, mesuré sur corpus réel.

Ce test est le contrat de la refonte : il rejoue `detect_paywall()` sur le
corpus de vérité terrain et **échoue si le nombre de faux positifs augmente sur
une seule source**, même si le nombre de faux négatifs s'effondre par ailleurs.

L'asymétrie est volontaire. Un faux négatif coûte un clic déçu. Un faux positif
masque définitivement un article gratuit (`_save_content` n'upgrade `is_paid`
que `False → True`) et rogne l'offre gratuite qui est la promesse de l'app.

Tant que le corpus n'est pas collecté et étiqueté, les tests se skippent avec
une raison explicite : un corpus absent ne doit jamais passer pour un corpus
sans erreur.
"""

import json

import pytest

from scripts.paywall_benchmark import BASELINE_PATH, evaluate, load_corpus

MIN_PAID_PER_SOURCE = 3
MIN_FREE_PER_SOURCE = 3


@pytest.fixture(scope="module")
def corpus():
    cases = load_corpus()
    if not cases:
        pytest.skip(
            "Corpus paywall non collecté ou non étiqueté — "
            "cf. scripts/build_paywall_corpus.py"
        )
    return cases


@pytest.fixture(scope="module")
def measured(corpus):
    return evaluate(corpus)


def test_corpus_has_free_articles_per_source(corpus):
    """Un corpus sans articles gratuits ne mesure aucun faux positif.

    C'est l'angle mort historique de la feature : on ne saurait pas dire si la
    détection masque déjà des articles gratuits aujourd'hui.
    """
    by_source: dict[str, dict[str, int]] = {}
    for case in corpus:
        counts = by_source.setdefault(case.source, {"paid": 0, "free": 0})
        counts[case.label] += 1

    incomplete = {
        slug: counts
        for slug, counts in by_source.items()
        if counts["free"] < MIN_FREE_PER_SOURCE or counts["paid"] < MIN_PAID_PER_SOURCE
    }
    assert not incomplete, (
        f"Sources sous quota {MIN_PAID_PER_SOURCE} payants / "
        f"{MIN_FREE_PER_SOURCE} gratuits : {incomplete}"
    )


def test_false_positive_rate_never_regresses(measured):
    """Critère bloquant : aucune source ne gagne de faux positif vs baseline."""
    if not BASELINE_PATH.exists():
        pytest.skip(
            "Aucune baseline gelée — "
            "PYTHONPATH=. python scripts/paywall_benchmark.py --write-baseline"
        )

    baseline = json.loads(BASELINE_PATH.read_text(encoding="utf-8"))
    overall, by_source = measured

    regressions = []
    for slug, matrix in sorted(by_source.items()):
        reference = baseline["by_source"].get(slug)
        if reference is None:
            continue  # source ajoutée après le gel : rien à comparer
        if matrix.fp > reference["fp"]:
            regressions.append(
                f"{slug}: {reference['fp']} → {matrix.fp} faux positifs "
                f"({[e['url'] for e in matrix.errors if e['kind'] == 'fp']})"
            )

    assert not regressions, "Régression de faux positifs :\n" + "\n".join(regressions)
    assert overall.fp <= baseline["overall"]["fp"], (
        f"Faux positifs globaux en hausse : {baseline['overall']['fp']} → {overall.fp}"
    )


def test_false_negative_rate_improves_on_reported_sources(measured):
    """Les 5 sources remontées par les utilisateurs doivent progresser.

    Sens inverse du test précédent : il échoue si une modification censée
    corriger les faux négatifs ne les corrige pas, pour éviter de merger un
    changement neutre au prétexte qu'il ne casse rien.
    """
    if not BASELINE_PATH.exists():
        pytest.skip("Aucune baseline gelée")

    baseline = json.loads(BASELINE_PATH.read_text(encoding="utf-8"))
    _, by_source = measured
    reported = ["novethic", "philomag", "la-croix", "lesjours", "cuisiner-jdf"]

    worsened = [
        f"{slug}: {baseline['by_source'][slug]['fn']} → {by_source[slug].fn}"
        for slug in reported
        if slug in by_source
        and slug in baseline["by_source"]
        and by_source[slug].fn > baseline["by_source"][slug]["fn"]
    ]
    assert not worsened, "Faux négatifs en hausse sur :\n" + "\n".join(worsened)
