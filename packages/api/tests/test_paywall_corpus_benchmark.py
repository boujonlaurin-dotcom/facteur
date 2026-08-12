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

### Ce qui tourne en CI, et ce qui ne tourne qu'en local

`labels.json` est versionné, `html/` et `rss/` ne le sont pas (contenu de presse
sous droits, repo public). La CI voit donc l'étiquetage mais **jamais** les
charges utiles. Les deux natures de test sont séparées en conséquence :

- le **quota** ne lit que `labels.json` + le manifeste, donc il tourne partout,
  y compris en CI, et garde la cohérence de l'étiquetage sous contrôle ;
- la **mesure** (matrice de confusion) exige le HTML capturé. Sans lui, chaque
  cas partirait avec `html_head=None`, le niveau 1 serait entièrement sauté et
  la matrice mesurerait un détecteur amputé — un faux vert, exactement ce que ce
  fichier existe pour empêcher. Elle se skippe donc faute de charges utiles.
"""

import json

import pytest

from scripts.build_paywall_corpus import load_labels, load_manifest, quota_status
from scripts.paywall_benchmark import BASELINE_PATH, evaluate, load_corpus


@pytest.fixture(scope="module")
def corpus():
    cases = load_corpus()
    if not cases:
        pytest.skip(
            "Corpus paywall non collecté ou non étiqueté — "
            "cf. scripts/build_paywall_corpus.py"
        )
    if not any(case.html_head for case in cases):
        pytest.skip(
            "Étiquetage présent mais charges utiles absentes (html/ et rss/ ne "
            "sont pas versionnés) : mesurer ici donnerait une matrice non "
            "représentative, tous les cas ayant html_head=None. "
            "Relancer PYTHONPATH=. python scripts/build_paywall_corpus.py"
        )
    return cases


@pytest.fixture(scope="module")
def measured(corpus):
    return evaluate(corpus)


def test_corpus_has_free_articles_per_source():
    """Un corpus sans articles gratuits ne mesure aucun faux positif.

    C'est l'angle mort historique de la feature : on ne saurait pas dire si la
    détection masque déjà des articles gratuits aujourd'hui.

    Le verdict ne porte que sur les sources dont l'étiquetage est **terminé**.
    Une source à moitié étiquetée n'est pas un corpus défaillant, c'est un
    travail en cours : la juger ferait échouer la suite pendant tout
    l'étiquetage, qui s'étale sur plusieurs sessions et se fait média par média.
    La règle exacte — et ses deux exemptions — vit dans `quota_status()`, avec
    le collecteur qui l'applique aussi.
    """
    status = quota_status(load_manifest(), load_labels())
    finished = {slug: state for slug, state in status.items() if state["complete"]}
    if not finished:
        reste = sum(state["unlabeled"] for state in status.values())
        pytest.skip(
            f"Aucune source entièrement étiquetée — {reste} articles restants "
            "dans labels.json. Le quota se juge source par source, une fois "
            "son étiquetage terminé."
        )

    manquantes = {
        slug: f"{state['paid']} payants / {state['free']} gratuits"
        for slug, state in finished.items()
        if not state["meets_quota"]
    }
    assert not manquantes, (
        "Sources entièrement étiquetées mais sous quota — il faut collecter "
        f"plus d'articles pour elles, pas en étiqueter davantage : {manquantes}"
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
