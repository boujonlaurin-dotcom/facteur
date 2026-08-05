"""Tests hermétiques pour `scripts/build_persona_dataset.py`.

Ni DB ni réseau : le script ne lit qu'un dump JSON (convention `--raw`, le rôle
RO étant refusé sur les tables `user_*`).

L'enjeu principal est le **déterminisme**. Toute la campagne de tuning repose
sur la comparabilité de deux runs ; si le clustering pouvait permuter d'une
exécution à l'autre, « même corpus + mêmes personas » cesserait de vouloir dire
quelque chose et `--compare` validerait des comparaisons fausses. D'où
k-medoids écrit à la main, sans `random` ni `numpy` (absent de
`requirements.txt`, donc de la CI).
"""

import json

import pytest

from scripts import build_persona_dataset as bp


def _user(key: str, *, sources: int, themes: int, topics: int, w: float, days: int):
    return {
        "user_key": key,
        "days_since_signup": days,
        "followed_sources": [
            {
                "source_id": f"22222222-2222-4222-8222-{i:012d}",
                "is_custom": False,
                "has_subscription": False,
                "priority_multiplier": 1.0,
                "state": "followed",
            }
            for i in range(sources)
        ],
        "interests": [
            {"slug": f"theme_{i}", "weight": w if i == 0 else 1.0, "state": "followed"}
            for i in range(themes)
        ],
        "subtopic_weights": {"ai": 1.0},
        "custom_topics": [
            {
                "topic_name": f"sujet_{i}",
                "slug_parent": "politics",
                "keywords": ["mot"],
                "priority_multiplier": 1.0,
                "state": "followed",
                "entity_type": None,
                "canonical_name": None,
            }
            for i in range(topics)
        ],
        "entity_affinities": {"openai": 0.5},
        "mutes": {
            "muted_sources": [],
            "muted_themes": [],
            "muted_topics": [],
            "muted_content_types": [],
        },
        "user_prefs": {"objective": "bias"},
    }


@pytest.fixture
def population() -> list[dict]:
    """20 comptes étalés : un gros noyau moyen, quelques gros profils, un J+1
    et deux comptes au plafond de `weight`."""
    users = [
        _user(f"u{i:02d}", sources=18 + i % 4, themes=5, topics=12, w=1.2, days=40 + i)
        for i in range(12)
    ]
    users += [
        _user("v00", sources=80, themes=10, topics=60, w=2.5, days=160),
        _user("v01", sources=75, themes=9, topics=55, w=2.4, days=150),
        # Trois comptes J+1. Les deux premiers sont si atypiques qu'ils sortent
        # eux-mêmes comme médoïdes ; `w02` reste dans le noyau et sert donc de
        # candidat libre à l'extrême « compte neuf ».
        _user("w00", sources=0, themes=0, topics=1, w=0.0, days=1),
        _user("w01", sources=1, themes=1, topics=2, w=0.5, days=1),
        _user("w02", sources=19, themes=5, topics=12, w=1.2, days=1),
        _user("x00", sources=40, themes=8, topics=30, w=3.0, days=90),
        _user("x01", sources=35, themes=7, topics=25, w=3.0, days=70),
        _user("y00", sources=25, themes=6, topics=20, w=2.0, days=110),
        _user("y01", sources=30, themes=6, topics=22, w=1.8, days=120),
    ]
    return sorted(users, key=lambda u: u["user_key"])


# ---------------------------------------------------------------------------
# Déterminisme
# ---------------------------------------------------------------------------


def test_clustering_is_deterministic(population):
    """Le cœur du contrat : deux exécutions sur le même dump donnent exactement
    les mêmes personas. Sans ça, deux runs de sensibilité ne se comparent plus."""
    first = bp.build_personas(population, bp.DEFAULT_K)
    second = bp.build_personas(population, bp.DEFAULT_K)
    assert json.dumps(first, sort_keys=True) == json.dumps(second, sort_keys=True)


def test_clustering_does_not_depend_on_dict_iteration_luck(population):
    """Recharger le dump depuis du JSON (donc de nouveaux objets) ne change
    rien : le tri se fait sur les valeurs, pas sur des identités d'objets."""
    reloaded = json.loads(json.dumps(population))
    assert bp.build_personas(population, bp.DEFAULT_K) == bp.build_personas(
        reloaded, bp.DEFAULT_K
    )


def test_no_random_module_is_imported():
    """Garde de régression : introduire `random` (même seedé) rouvrirait la
    porte au non-déterminisme entre versions de Python."""
    source = bp.__file__
    with open(source, encoding="utf-8") as handle:
        text = handle.read()
    assert "import random" not in text
    assert "import numpy" not in text


# ---------------------------------------------------------------------------
# Forme du résultat
# ---------------------------------------------------------------------------


def test_eight_personas_six_medoids_then_two_extremes(population):
    personas = bp.build_personas(population, bp.DEFAULT_K)
    assert [p["persona_id"] for p in personas] == [
        f"persona_{i:02d}" for i in range(1, 9)
    ]
    assert [p["selection"] for p in personas[:6]] == ["cluster_medoid"] * 6
    assert personas[6]["selection"] == "extreme_veteran"
    assert personas[7]["selection"] == "extreme_fresh_account"


def test_the_two_extremes_are_the_heldout_set(population):
    """`--gold` tient les deux derniers en held-out : l'ordre n'est pas
    cosmétique, il porte la garde anti-overfit."""
    personas = bp.build_personas(population, bp.DEFAULT_K)
    assert [p["is_heldout"] for p in personas] == [False] * 6 + [True, True]


def test_a_population_without_extremes_yields_fewer_personas(population):
    """Sans compte au plafond ni compte J+1, il n'y a que les médoïdes. Le
    script produit alors **moins de 8 personas** — c'est légitime, mais ça doit
    rester visible : le held-out du mode `--gold` est réduit d'autant."""
    ordinary = [
        u
        for u in population
        if bp._max_weight(u) < bp.INTEREST_WEIGHT_CAP
        and u["days_since_signup"] > bp.FRESH_ACCOUNT_MAX_DAYS
    ]
    personas = bp.build_personas(ordinary, bp.DEFAULT_K)
    assert len(personas) == bp.DEFAULT_K
    assert all(p["selection"] == "cluster_medoid" for p in personas)
    assert not any(p["is_heldout"] for p in personas)


def test_personas_are_distinct_accounts(population):
    """Un extrême déjà retenu comme médoïde est sauté : huit personas dont deux
    seraient le même compte n'apporteraient rien.

    La signature porte sur le **profil complet**, pas sur les seuls `interests`
    — deux comptes distincts peuvent parfaitement suivre les mêmes thèmes.
    """
    assigned = {"persona_id", "selection", "is_heldout", "cluster_size", "archetype"}
    signatures = {
        json.dumps({k: v for k, v in p.items() if k not in assigned}, sort_keys=True)
        for p in bp.build_personas(population, bp.DEFAULT_K)
    }
    assert len(signatures) == bp.DEFAULT_K + 2


def test_cluster_sizes_cover_the_whole_population(population):
    """La somme des tailles de cluster doit rendre compte de tous les comptes —
    sinon `cluster_size` ne veut plus dire « combien de comptes je représente »."""
    personas = bp.build_personas(population, bp.DEFAULT_K)
    medoid_sizes = [
        p["cluster_size"] for p in personas if p["selection"] == "cluster_medoid"
    ]
    assert sum(medoid_sizes) == len(population)


def test_the_veteran_is_taken_at_the_weight_cap(population):
    personas = bp.build_personas(population, bp.DEFAULT_K)
    veteran = personas[6]
    assert max(v["weight"] for v in veteran["interests"].values()) == pytest.approx(
        bp.INTEREST_WEIGHT_CAP
    )
    # Il représente le nombre réel de comptes au plafond, pas 1.
    assert veteran["cluster_size"] == 2


def test_the_fresh_account_is_the_youngest(population):
    personas = bp.build_personas(population, bp.DEFAULT_K)
    assert personas[7]["days_since_signup"] <= bp.FRESH_ACCOUNT_MAX_DAYS


# ---------------------------------------------------------------------------
# Anonymisation
# ---------------------------------------------------------------------------


def _all_strings(node) -> set[str]:
    """Toutes les chaînes (clés et valeurs) d'une structure imbriquée."""
    if isinstance(node, dict):
        out = set(node)
        for value in node.values():
            out |= _all_strings(value)
        return out
    if isinstance(node, list):
        return set().union(*(_all_strings(v) for v in node)) if node else set()
    return {node} if isinstance(node, str) else set()


def test_personas_carry_no_account_identifier(population):
    """`user_key` est la clé de jointure **du dump**, elle ne doit jamais
    atteindre la fixture versionnée.

    Le contrôle porte sur les chaînes **parsées**, pas sur le JSON sérialisé :
    un `u00` cherché en sous-chaîne matcherait l'échappement `\\u00b7` du « · »
    des archétypes et rendrait le test faussement rouge.
    """
    personas = bp.build_personas(population, bp.DEFAULT_K)
    strings = _all_strings(personas)
    assert "user_key" not in strings
    assert "user_id" not in strings
    assert not strings & {user["user_key"] for user in population}


def test_catalogue_identifiers_are_deliberately_kept(population):
    """Les `source_id` et slugs de thèmes sont des identifiants de catalogue
    partagés, pas des données personnelles — et le scoring en dépend."""
    persona = bp.build_personas(population, bp.DEFAULT_K)[0]
    assert persona["followed_sources"] or persona["interests"]
    assert isinstance(persona["subtopic_weights"], dict)


# ---------------------------------------------------------------------------
# Briques numériques
# ---------------------------------------------------------------------------


def test_zscore_neutralises_a_constant_column():
    """Écart-type nul → colonne à 0 : une feature constante ne doit rien peser
    dans la distance, et surtout pas diviser par zéro."""
    matrix = [[1.0, 5.0], [2.0, 5.0], [3.0, 5.0]]
    scaled = bp.zscore(matrix)
    assert [row[1] for row in scaled] == [0.0, 0.0, 0.0]
    assert scaled[0][0] < 0 < scaled[2][0]


def test_zscore_on_empty_input():
    assert bp.zscore([]) == []


def test_features_reads_the_five_axes():
    user = _user("z", sources=3, themes=2, topics=4, w=2.5, days=7)
    assert bp.features(user) == [3.0, 2.0, 4.0, 2.5, 7.0]
    assert len(bp.FEATURE_NAMES) == 5


def test_features_tolerate_an_empty_account():
    empty = {"user_key": "e", "days_since_signup": 0}
    assert bp.features(empty) == [0.0, 0.0, 0.0, 0.0, 0.0]


def test_kmedoids_returns_distinct_medoids(population):
    points = bp.zscore([bp.features(u) for u in population])
    medoids, assignment = bp.kmedoids(points, bp.DEFAULT_K)
    assert len(set(medoids)) == bp.DEFAULT_K
    assert len(assignment) == len(population)
    assert set(assignment) <= set(range(bp.DEFAULT_K))


def test_kmedoids_handles_fewer_points_than_clusters():
    points = bp.zscore([[1.0, 1.0], [5.0, 5.0]])
    medoids, assignment = bp.kmedoids(points, 6)
    assert len(medoids) == 2
    assert len(assignment) == 2


def test_the_dump_sql_stays_in_the_script():
    """Le SQL est la source de vérité du format d'entrée : s'il migrait dans un
    doc, il dériverait du parseur sans que rien ne le signale."""
    assert "user_personalization" in bp.PERSONA_DUMP_SQL
    for table in (
        "user_sources",
        "user_interests",
        "user_subtopics",
        "user_topic_profiles",
        "user_entity_affinity",
        "user_preferences",
    ):
        assert table in bp.PERSONA_DUMP_SQL
