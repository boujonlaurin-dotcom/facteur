"""Tests du cœur de regroupement par sujet (`briefing/topic_clustering`).

Les cas de non-régression viennent de corpus de production réels documentés dans
`docs/bugs/bug-clustering-actus-du-jour-fragmentation.md` :

- **Ceuta** : 21 médias couvrant le même événement, que l'algorithme historique
  éclatait en 19 clusters (0 sujet « trending »).
- **Trump** : des sujets distincts (accord Hamas / missiles Patriot en Ukraine)
  partageant une entité très visible, qui ne doivent PAS fusionner — c'est la
  régression « Texas » de `bug-comparison-clustering-too-loose.md`.
"""

from app.services.briefing.topic_clustering import (
    build_vectors,
    cluster_documents,
    compute_idf,
)
from app.services.text_similarity import normalize_title

CEUTA_TITLES = [
    "Crise migratoire à Ceuta: pourquoi cet afflux dans l'enclave espagnole ?",
    "L'enclave espagnole de Ceuta face à un afflux massif de migrants",
    "L'enclave espagnole de Ceuta débordée par une arrivée massive de migrants",
    "Arrivée massive de migrants à Ceuta : au moins 18 morts",
    "Urgence humanitaire : arrivée massive de migrants à Ceuta",
    "Un afflux massif de migrants à Ceuta ravive les tensions entre Madrid et Rabat",
    "Ceuta : un afflux massif de migrants en provenance du Maroc fait au moins 27 morts",
]

GAZA_TITLES = [
    "Gaza : Trump annonce un accord sur le désarmement du Hamas",
    "Donald Trump annonce un accord sur le désarmement du Hamas à Gaza",
    "Gaza : que prévoit l'accord sur le désarmement du Hamas annoncé par Donald Trump ?",
]

UKRAINE_TITLES = [
    "Guerre en Ukraine : Donald Trump finalement pas sûr d'accorder son feu vert "
    "à Kiev pour fabriquer des missiles Patriot",
    "Donald Trump n'est pas certain qu'il laissera l'Ukraine produire des missiles Patriot",
]

UNRELATED_TITLES = [
    "Ligue 1 : le PSG s'impose face à Marseille",
    "La BCE maintient ses taux directeurs inchangés",
    "Grippe aviaire : un nouveau foyer détecté en Bretagne",
]


def _cluster(titles: list[str], threshold: float = 0.30) -> list[list[int]]:
    return cluster_documents([normalize_title(t) for t in titles], threshold)


def _group_of(groups: list[list[int]], index: int) -> list[int]:
    return next(g for g in groups if index in g)


class TestComputeIdf:
    def test_rare_token_weighs_more_than_common_one(self):
        token_sets = [{"ceuta", "migrants"}, {"migrants", "psg"}, {"migrants", "bce"}]
        idf = compute_idf(token_sets)

        assert idf["ceuta"] > idf["migrants"]

    def test_token_present_everywhere_keeps_positive_weight(self):
        """Le lissage évite les vecteurs nuls quand deux titres sont identiques."""
        idf = compute_idf([{"macron", "dissolution"}, {"macron", "dissolution"}])

        assert all(w > 0 for w in idf.values())

    def test_identical_documents_produce_usable_vectors(self):
        token_sets = [{"macron", "dissolution"}, {"macron", "dissolution"}]
        vectors = build_vectors(token_sets, compute_idf(token_sets))

        assert all(v for v in vectors)


class TestClusterDocuments:
    def test_empty_input(self):
        assert cluster_documents([], 0.30) == []

    def test_every_document_appears_exactly_once(self):
        titles = CEUTA_TITLES + GAZA_TITLES + UNRELATED_TITLES
        groups = _cluster(titles)

        assert sorted(i for g in groups for i in g) == list(range(len(titles)))

    def test_short_titles_stay_singletons(self):
        """Sous le minimum de tokens, on ne peut pas regrouper de façon fiable."""
        groups = cluster_documents([{"gaza"}, {"gaza"}], threshold=0.30, min_tokens=3)

        assert sorted(len(g) for g in groups) == [1, 1]

    def test_unrelated_topics_are_not_merged(self):
        groups = _cluster(UNRELATED_TITLES)

        assert len(groups) == 3


class TestCeutaRegression:
    """Le sujet le plus couvert du jour doit former UN cluster, pas 19 singletons."""

    def test_same_event_is_grouped(self):
        groups = _cluster(CEUTA_TITLES)
        biggest = max(groups, key=len)

        assert len(biggest) >= 5, f"Ceuta éclaté en {len(groups)} clusters"

    def test_stays_grouped_when_diluted_in_unrelated_news(self):
        titles = CEUTA_TITLES + UNRELATED_TITLES
        groups = _cluster(titles)
        biggest = max(groups, key=len)

        assert len(biggest) >= 5
        # Aucun article sans rapport n'a été absorbé.
        assert all(i < len(CEUTA_TITLES) for i in biggest)


class TestNoTexasRegression:
    """Deux sujets distincts liés par une entité très visible ne doivent pas fusionner."""

    def test_gaza_and_ukraine_stay_separate_despite_shared_trump(self):
        titles = GAZA_TITLES + UKRAINE_TITLES
        groups = _cluster(titles)

        gaza_group = _group_of(groups, 0)
        ukraine_index = len(GAZA_TITLES)

        assert ukraine_index not in gaza_group
        assert all(i < len(GAZA_TITLES) for i in gaza_group)

    def test_each_subject_is_internally_grouped(self):
        titles = GAZA_TITLES + UKRAINE_TITLES
        groups = _cluster(titles)

        assert len(_group_of(groups, 0)) >= 2  # les titres Gaza se retrouvent
        assert len(_group_of(groups, len(GAZA_TITLES))) >= 2  # idem Ukraine


class TestClusterGrowthIsNotPenalised:
    """Régression du défaut historique : le cluster se refermait après 2 articles."""

    def test_cluster_keeps_absorbing_beyond_two_articles(self):
        groups = _cluster(CEUTA_TITLES)
        biggest = max(groups, key=len)

        assert len(biggest) > 2
